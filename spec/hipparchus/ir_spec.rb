# frozen_string_literal: true

RSpec.describe Hipparchus::IR do
  def column(name, **overrides)
    Hipparchus::IR::Column.new(
      **{ name: name, type: :string, sql_type: "text", null: true, default: nil,
          primary_key: false, comment: nil, position: 1 }.merge(overrides)
    )
  end

  def table(name, **overrides)
    Hipparchus::IR::Table.new(
      **{ name: name, schema: "public", comment: nil, columns: [],
          primary_key: [], foreign_keys: [], indexes: [] }.merge(overrides)
    )
  end

  describe Hipparchus::IR::Table do
    it "qualifies its name with the schema" do
      expect(table("users").qualified_name).to eq("public.users")
    end

    it "omits the dot when unqualified" do
      expect(table("users", schema: nil).qualified_name).to eq("users")
    end

    it "looks up a column by name" do
      t = table("users", columns: [column("id"), column("email")])
      expect(t.column("email").name).to eq("email")
      expect(t.column("missing")).to be_nil
    end

    it "is immutable" do
      expect { table("users").name = "x" }.to raise_error(NoMethodError)
    end

    it "compares by value" do
      expect(table("users")).to eq(table("users"))
    end
  end

  describe Hipparchus::IR::ForeignKey do
    it "qualifies the referenced table" do
      fk = Hipparchus::IR::ForeignKey.new(
        name: "fk", columns: %w[author_id], to_table: "authors", to_schema: "public",
        primary_key: %w[id], on_delete: :cascade, on_update: nil
      )
      expect(fk.qualified_to).to eq("public.authors")
    end
  end

  describe Hipparchus::IR::Schema do
    let(:schema) do
      described_class.new(
        adapter: "postgresql", database: "app",
        tables: [table("users"), table("orders", schema: "billing")],
        extracted_at: Time.now
      )
    end

    it "finds a table by bare name" do
      expect(schema.table("users").name).to eq("users")
    end

    it "finds a table by qualified name" do
      expect(schema.table("billing.orders").schema).to eq("billing")
      expect(schema.table("public.orders")).to be_nil
    end
  end
end
