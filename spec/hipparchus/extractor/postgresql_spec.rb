# frozen_string_literal: true

RSpec.describe Hipparchus::Extractor::PostgreSQL do
  let(:connection) { HipparchusTest.postgres_connection }
  let(:raw_connection) { connection&.raw_connection }

  subject(:schema) { Hipparchus.extract(connection: connection, raw_connection: raw_connection) }

  before do
    skip "set #{HipparchusTest::DATABASE_URL_ENV} to a PostgreSQL URL to run these specs" unless connection

    connection.execute(<<~SQL)
      DROP SCHEMA IF EXISTS hipparchus_test CASCADE;
      CREATE SCHEMA hipparchus_test;
      SET search_path TO hipparchus_test;

      CREATE TABLE authors (
        id   bigserial PRIMARY KEY,
        name varchar(255) NOT NULL
      );
      COMMENT ON TABLE authors IS 'People who write books';
      COMMENT ON COLUMN authors.name IS 'Display name';

      CREATE TABLE books (
        id        bigserial PRIMARY KEY,
        author_id bigint NOT NULL REFERENCES authors (id) ON DELETE CASCADE,
        isbn      varchar(20),
        title     text NOT NULL
      );
      CREATE UNIQUE INDEX index_books_on_isbn ON books (isbn) WHERE isbn IS NOT NULL;
      CREATE INDEX index_books_on_lower_title ON books (lower(title));

      CREATE TABLE book_translations (
        book_id  bigint  NOT NULL,
        language char(2) NOT NULL,
        title    text    NOT NULL,
        PRIMARY KEY (book_id, language),
        FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE ON UPDATE RESTRICT
      );

      CREATE TABLE editions (
        book_id  bigint      NOT NULL,
        language char(2)     NOT NULL,
        format   varchar(20) NOT NULL,
        PRIMARY KEY (book_id, language, format),
        FOREIGN KEY (book_id, language)
          REFERENCES book_translations (book_id, language) ON DELETE CASCADE
      );
    SQL
  end

  after { connection&.execute("DROP SCHEMA IF EXISTS hipparchus_test CASCADE") }

  it "reports the adapter" do
    expect(schema.adapter).to eq("postgresql")
  end

  describe "a table" do
    let(:authors) { schema.table("hipparchus_test.authors") }

    it "carries its comment and primary key" do
      expect(authors.comment).to eq("People who write books")
      expect(authors.primary_key).to eq(%w[id])
    end

    it "describes the surrogate key column" do
      id = authors.column("id")
      expect(id.type).to eq(:integer)
      expect(id.primary_key).to be(true)
      expect(id.null).to be(false)
      expect(id.default).to match(/nextval/)
    end

    it "describes an ordinary column with its comment and raw type" do
      name = authors.column("name")
      expect(name.type).to eq(:string)
      expect(name.sql_type).to eq("character varying(255)")
      expect(name.null).to be(false)
      expect(name.comment).to eq("Display name")
      expect(name.primary_key).to be(false)
    end
  end

  describe "a single-column foreign key" do
    let(:fk) { schema.table("hipparchus_test.books").foreign_keys.first }

    it "points at the referenced table with its action" do
      expect(fk.columns).to eq(%w[author_id])
      expect(fk.to_table).to eq("authors")
      expect(fk.to_schema).to eq("hipparchus_test")
      expect(fk.primary_key).to eq(%w[id])
      expect(fk.on_delete).to eq(:cascade)
      expect(fk.on_update).to eq(:no_action)
    end
  end

  describe "a composite primary key" do
    it "preserves column order" do
      expect(schema.table("hipparchus_test.book_translations").primary_key).to eq(%w[book_id language])
      expect(schema.table("hipparchus_test.editions").primary_key).to eq(%w[book_id language format])
    end
  end

  describe "a composite foreign key" do
    let(:fk) { schema.table("hipparchus_test.editions").foreign_keys.first }

    it "keeps local and referenced columns aligned and ordered" do
      expect(fk.columns).to eq(%w[book_id language])
      expect(fk.primary_key).to eq(%w[book_id language])
      expect(fk.to_table).to eq("book_translations")
      expect(fk.on_delete).to eq(:cascade)
    end
  end

  describe "referential actions other than the default" do
    let(:fk) { schema.table("hipparchus_test.book_translations").foreign_keys.first }

    it "distinguishes on_update from on_delete" do
      expect(fk.on_delete).to eq(:cascade)
      expect(fk.on_update).to eq(:restrict)
    end
  end

  describe "a partial unique index" do
    let(:index) do
      schema.table("hipparchus_test.books").indexes.find { |i| i.name == "index_books_on_isbn" }
    end

    it "captures uniqueness, columns and the predicate" do
      expect(index).not_to be_nil
      expect(index.unique).to be(true)
      expect(index.columns).to eq(%w[isbn])
      expect(index.where).to match(/isbn/)
      expect(index.using).to eq("btree")
    end

    it "does not surface the primary key as an index" do
      names = schema.table("hipparchus_test.books").indexes.map(&:name)
      expect(names).not_to include("books_pkey")
    end
  end

  describe "an expression index" do
    let(:index) do
      schema.table("hipparchus_test.books").indexes.find { |i| i.name == "index_books_on_lower_title" }
    end

    it "records the expression text in place of a column name" do
      expect(index.columns).to eq(["lower(title)"])
    end
  end
end
