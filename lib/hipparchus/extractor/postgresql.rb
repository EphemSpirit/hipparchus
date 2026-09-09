# frozen_string_literal: true

require_relative "base"

module Hipparchus
  module Extractor
    # Extracts a {Hipparchus::IR::Schema} from a PostgreSQL database.
    #
    # All schema information is read straight from the system catalogs through
    # the raw driver connection (+@raw_connection+, typically a +PG::Connection+).
    # The ActiveRecord connection is used only for the database name. Catalogs are
    # queried once each for the whole database (not per table), then grouped in
    # Ruby by table OID.
    #
    # Reading the catalogs directly - rather than through ActiveRecord's schema
    # statements - is what lets this report composite foreign keys, referential
    # actions, partial-index predicates and comments uniformly.
    class PostgreSQL < Base
      # Non-user schemas that are never part of an ERD.
      SYSTEM_SCHEMAS = %w[pg_catalog information_schema pg_toast].freeze

      # PostgreSQL base type name -> normalized logical type.
      LOGICAL_TYPES = {
        "int2" => :integer, "int4" => :integer, "int8" => :integer,
        "numeric" => :decimal, "money" => :decimal,
        "float4" => :float, "float8" => :float,
        "bool" => :boolean,
        "varchar" => :string, "bpchar" => :string, "char" => :string,
        "name" => :string, "citext" => :string,
        "text" => :text, "xml" => :text,
        "date" => :date,
        "time" => :time, "timetz" => :time,
        "timestamp" => :datetime, "timestamptz" => :datetime,
        "uuid" => :uuid,
        "json" => :json, "jsonb" => :json,
        "bytea" => :binary
      }.freeze

      # PostgreSQL +confdeltype+ / +confupdtype+ code -> referential action.
      FK_ACTIONS = {
        "a" => :no_action, "r" => :restrict, "c" => :cascade,
        "n" => :nullify, "d" => :set_default
      }.freeze

      # @return [Hipparchus::IR::Schema]
      def call
        columns = fetch_columns.group_by { |r| r["table_oid"] }
        primary_keys = group_primary_keys(fetch_primary_keys)
        foreign_keys = group_foreign_keys(fetch_foreign_keys)
        indexes = group_indexes(fetch_indexes)

        tables = fetch_tables.map do |row|
          oid = row["table_oid"]
          pk = primary_keys[oid] || []
          IR::Table.new(
            name: row["name"],
            schema: row["schema"],
            comment: presence(row["comment"]),
            columns: (columns[oid] || []).map { |c| build_column(c, pk) },
            primary_key: pk,
            foreign_keys: foreign_keys[oid] || [],
            indexes: indexes[oid] || []
          )
        end

        IR::Schema.new(
          adapter: "postgresql",
          database: database_name,
          tables: tables,
          extracted_at: Time.now
        )
      end

      private

      def build_column(row, primary_key)
        IR::Column.new(
          name: row["name"],
          type: LOGICAL_TYPES.fetch(row["base_type"], :other),
          sql_type: row["sql_type"],
          null: pg_bool(row["nullable"]),
          default: presence(row["default"]),
          primary_key: primary_key.include?(row["name"]),
          comment: presence(row["comment"]),
          position: row["position"].to_i
        )
      end

      def group_primary_keys(rows)
        rows.group_by { |r| r["table_oid"] }
            .transform_values { |rs| rs.map { |r| r["column"] } }
      end

      def group_foreign_keys(rows)
        by_oid = Hash.new { |h, k| h[k] = {} }
        rows.each do |row|
          fk = by_oid[row["table_oid"]][row["constraint_oid"]] ||= {
            name: presence(row["name"]),
            to_table: row["to_table"],
            to_schema: row["to_schema"],
            columns: [],
            primary_key: [],
            on_delete: FK_ACTIONS[row["on_delete"]],
            on_update: FK_ACTIONS[row["on_update"]]
          }
          fk[:columns] << row["column"]
          fk[:primary_key] << row["to_column"]
        end
        by_oid.transform_values { |fks| fks.values.map { |h| IR::ForeignKey.new(**h) } }
      end

      def group_indexes(rows)
        by_oid = Hash.new { |h, k| h[k] = {} }
        rows.each do |row|
          idx = by_oid[row["table_oid"]][row["index_oid"]] ||= {
            name: row["name"],
            columns: [],
            unique: pg_bool(row["unique"]),
            using: presence(row["using"]),
            where: presence(row["where"])
          }
          idx[:columns] << row["column"] if row["column"]
        end
        by_oid.transform_values { |idxs| idxs.values.map { |h| IR::Index.new(**h) } }
      end

      # One row per user table. Reads +pg_class+ (every relation) joined to
      # +pg_namespace+ for the schema name, keeping only +relkind+ 'r'
      # (ordinary table) and 'p' (partitioned-table parent) and dropping
      # system/temp schemas via {#user_schema_filter}. +obj_description+ pulls
      # the table's +COMMENT ON TABLE+ text. The +table_oid+ it returns
      # (+pg_class.oid+) is the key every other +fetch_*+ result is grouped by.
      def fetch_tables
        query(<<~SQL)
          SELECT c.oid AS table_oid,
                 n.nspname AS schema,
                 c.relname AS name,
                 obj_description(c.oid, 'pg_class') AS comment
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE c.relkind IN ('r', 'p')
            #{user_schema_filter("n")}
          ORDER BY n.nspname, c.relname
        SQL
      end

      # One row per column across every user table. Driven by +pg_attribute+,
      # joined to +pg_class+ / +pg_namespace+ (to filter by +relkind+ and
      # schema), +pg_type+ (raw type name) and, via LEFT JOIN, +pg_attrdef+
      # (default expression - absent for most columns). +attnum > 0+ skips
      # system columns such as +ctid+ / +xmin+; +NOT attisdropped+ skips the
      # tombstone rows left behind by +DROP COLUMN+. +format_type+ renders the
      # type with its modifiers (e.g. "numeric(10,2)"), +typname+ gives the
      # bare base type for the {LOGICAL_TYPES} lookup, and +attnotnull+ is
      # negated into a "nullable" flag. Ordered by +attnum+ so columns come
      # out in definition order.
      def fetch_columns
        query(<<~SQL)
          SELECT a.attrelid AS table_oid,
                 a.attname AS name,
                 a.attnum AS position,
                 format_type(a.atttypid, a.atttypmod) AS sql_type,
                 t.typname AS base_type,
                 (NOT a.attnotnull) AS nullable,
                 pg_get_expr(ad.adbin, ad.adrelid) AS default,
                 col_description(a.attrelid, a.attnum) AS comment
          FROM pg_attribute a
          JOIN pg_class c ON c.oid = a.attrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
          JOIN pg_type t ON t.oid = a.atttypid
          LEFT JOIN pg_attrdef ad ON ad.adrelid = a.attrelid AND ad.adnum = a.attnum
          WHERE c.relkind IN ('r', 'p')
            AND a.attnum > 0
            AND NOT a.attisdropped
            #{user_schema_filter("n")}
          ORDER BY a.attrelid, a.attnum
        SQL
      end

      # One row per primary-key column (+contype = 'p'+ in +pg_constraint+).
      # +con.conkey+ is a +smallint[]+ of the table's PK column numbers;
      # unnesting it +WITH ORDINALITY+ preserves the column order within a
      # composite key, and the join to +pg_attribute+ resolves each number to
      # a column name. Ordered by that ordinality so multi-column keys stay
      # in order.
      def fetch_primary_keys
        query(<<~SQL)
          SELECT con.conrelid AS table_oid,
                 a.attname AS column
          FROM pg_constraint con
          JOIN pg_class c ON c.oid = con.conrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
          JOIN LATERAL unnest(con.conkey) WITH ORDINALITY AS k(attnum, ord) ON TRUE
          JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = k.attnum
          WHERE con.contype = 'p'
            #{user_schema_filter("n")}
          ORDER BY con.conrelid, k.ord
        SQL
      end

      # One row per (foreign key, referencing column) pair. +contype = 'f'+ in
      # +pg_constraint+; +conrelid+ is the local table, +confrelid+ the
      # referenced table (joined through +pg_class+ / +pg_namespace+ on both
      # sides, as c/n and fc/fn). +conkey+ and +confkey+ are parallel
      # +smallint[]+ arrays of the local and referenced column numbers -
      # unnesting them together +WITH ORDINALITY+ pairs them up positionally
      # and keeps composite keys ordered. +la+ / +ra+ resolve those numbers to
      # local and referenced column names. +confdeltype+ / +confupdtype+ are
      # the +ON DELETE+ / +ON UPDATE+ action codes, mapped through
      # {FK_ACTIONS}. Rows are regrouped into one FK per +constraint_oid+ in
      # {#group_foreign_keys}.
      def fetch_foreign_keys
        query(<<~SQL)
          SELECT con.oid AS constraint_oid,
                 con.conname AS name,
                 con.conrelid AS table_oid,
                 la.attname AS column,
                 fn.nspname AS to_schema,
                 fc.relname AS to_table,
                 ra.attname AS to_column,
                 con.confdeltype AS on_delete,
                 con.confupdtype AS on_update
          FROM pg_constraint con
          JOIN pg_class c ON c.oid = con.conrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
          JOIN pg_class fc ON fc.oid = con.confrelid
          JOIN pg_namespace fn ON fn.oid = fc.relnamespace
          JOIN LATERAL unnest(con.conkey, con.confkey) WITH ORDINALITY AS k(local_attnum, remote_attnum, ord) ON TRUE
          JOIN pg_attribute la ON la.attrelid = con.conrelid AND la.attnum = k.local_attnum
          JOIN pg_attribute ra ON ra.attrelid = con.confrelid AND ra.attnum = k.remote_attnum
          WHERE con.contype = 'f'
            #{user_schema_filter("n")}
          ORDER BY con.conrelid, con.oid, k.ord
        SQL
      end

      # One row per (index, column) pair for every non-primary-key index on a
      # user table (+NOT indisprimary+). +pg_index+ holds the metadata:
      # +indexrelid+ is the index, +indrelid+ the table. +indkey+ is an
      # +int2vector+ of column numbers stored space-separated - it is cast to
      # text, split, and unnested +WITH ORDINALITY+ to keep column order. The
      # LEFT JOIN to +pg_attribute+ resolves plain column references; an entry
      # of 0 marks an expression index position, so +pg_get_indexdef+ recovers
      # that expression's SQL text (and +pg_get_expr(indpred, ...)+ the
      # partial-index +WHERE+ predicate). +indisunique+ and +amname+ (access
      # method, e.g. btree/gin) round out each index, which is reassembled
      # per +indexrelid+ in {#group_indexes}.
      def fetch_indexes
        query(<<~SQL)
          SELECT i.indexrelid AS index_oid,
                 ic.relname AS name,
                 i.indrelid AS table_oid,
                 i.indisunique AS unique,
                 am.amname AS using,
                 pg_get_expr(i.indpred, i.indrelid) AS where,
                 COALESCE(a.attname, pg_get_indexdef(i.indexrelid, k.ord::int, TRUE)) AS column
          FROM pg_index i
          JOIN pg_class ic ON ic.oid = i.indexrelid
          JOIN pg_class c ON c.oid = i.indrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
          JOIN pg_am am ON am.oid = ic.relam
          JOIN LATERAL unnest(string_to_array(i.indkey::text, ' ')) WITH ORDINALITY AS k(attnum, ord) ON TRUE
          LEFT JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum::int
          WHERE c.relkind IN ('r', 'p')
            AND NOT i.indisprimary
            #{user_schema_filter("n")}
          ORDER BY i.indrelid, i.indexrelid, k.ord
        SQL
      end

      def user_schema_filter(alias_name)
        list = SYSTEM_SCHEMAS.map { |s| "'#{s}'" }.join(", ")
        "AND #{alias_name}.nspname NOT IN (#{list}) " \
          "AND #{alias_name}.nspname NOT LIKE 'pg\\_temp\\_%' " \
          "AND #{alias_name}.nspname NOT LIKE 'pg\\_toast\\_temp\\_%'"
      end

      def query(sql)
        @raw_connection.exec(sql).to_a
      end

      def pg_bool(value)
        [true, "t"].include?(value)
      end

      def presence(string)
        string unless string.nil? || string.empty?
      end

      def database_name
        return unless @connection.respond_to?(:current_database)

        @connection.current_database
      end
    end
  end
end
