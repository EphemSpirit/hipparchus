# frozen_string_literal: true

module Hipparchus
  # The intermediate representation (IR): a database-agnostic description of a
  # relational schema. Extractors produce it; later stages (layout, rendering)
  # consume it. Every object is an immutable value.
  module IR
    # A whole schema snapshot.
    #
    # @!attribute adapter
    #   @return [String] the adapter that produced this, e.g. "postgresql"
    # @!attribute database
    #   @return [String, nil] the database name
    # @!attribute tables
    #   @return [Array<Table>] sorted by (schema, name)
    # @!attribute extracted_at
    #   @return [Time] when the snapshot was taken
    Schema = Data.define(:adapter, :database, :tables, :extracted_at) do
      # @param name [String] optionally schema-qualified ("public.users")
      # @return [Table, nil]
      def table(name)
        if name.include?(".")
          schema, bare = name.split(".", 2)
          tables.find { |t| t.schema == schema && t.name == bare }
        else
          tables.find { |t| t.name == name }
        end
      end
    end

    # A table (entity).
    #
    # @!attribute name          [String]
    # @!attribute schema        [String, nil] namespace, e.g. "public"
    # @!attribute comment       [String, nil]
    # @!attribute columns       [Array<Column>] in ordinal position order
    # @!attribute primary_key   [Array<String>] column names, in key order ([] if none)
    # @!attribute foreign_keys  [Array<ForeignKey>]
    # @!attribute indexes       [Array<Index>] excludes the primary key index
    Table = Data.define(:name, :schema, :comment, :columns, :primary_key, :foreign_keys, :indexes) do
      # @return [String] "schema.name", or just "name" when unqualified
      def qualified_name
        schema ? "#{schema}.#{name}" : name
      end

      # @param name [String]
      # @return [Column, nil]
      def column(name)
        columns.find { |c| c.name == name }
      end
    end

    # A column (attribute).
    #
    # @!attribute name         [String]
    # @!attribute type         [Symbol] normalized logical type (:integer, :string, ...)
    # @!attribute sql_type     [String] raw database type, e.g. "character varying(255)"
    # @!attribute null         [Boolean] whether NULL is allowed
    # @!attribute default      [String, nil] raw default expression
    # @!attribute primary_key  [Boolean] whether this column participates in the PK
    # @!attribute comment      [String, nil]
    # @!attribute position     [Integer] 1-based ordinal position
    Column = Data.define(:name, :type, :sql_type, :null, :default, :primary_key, :comment, :position)

    # A foreign key (relationship). Composite keys are represented by the ordered
    # +columns+ / +primary_key+ arrays.
    #
    # @!attribute name         [String, nil] constraint name
    # @!attribute columns      [Array<String>] local column names, in key order
    # @!attribute to_table     [String] referenced table
    # @!attribute to_schema    [String, nil] referenced table's schema
    # @!attribute primary_key  [Array<String>] referenced column names, in key order
    # @!attribute on_delete    [Symbol, nil] :no_action | :restrict | :cascade | :nullify | :set_default
    # @!attribute on_update    [Symbol, nil] same domain as on_delete
    ForeignKey = Data.define(:name, :columns, :to_table, :to_schema, :primary_key, :on_delete, :on_update) do
      # @return [String] qualified referenced table name
      def qualified_to
        to_schema ? "#{to_schema}.#{to_table}" : to_table
      end
    end

    # An index. Helps later stages infer cardinality (a unique index over a FK's
    # columns implies 1:1 rather than 1:many).
    #
    # @!attribute name     [String]
    # @!attribute columns  [Array<String>] indexed column names (expression parts omitted)
    # @!attribute unique   [Boolean]
    # @!attribute using    [String, nil] access method, e.g. "btree"
    # @!attribute where    [String, nil] predicate for a partial index
    Index = Data.define(:name, :columns, :unique, :using, :where)
  end
end
