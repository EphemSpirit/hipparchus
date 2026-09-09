# frozen_string_literal: true

RSpec.describe Hipparchus do
  it "has a version number" do
    expect(Hipparchus::VERSION).not_to be_nil
  end

  describe ".extract" do
    it "raises for an adapter without an extractor" do
      connection = Struct.new(:adapter_name).new("Mysql2")

      expect { described_class.extract(connection: connection, raw_connection: Object.new) }
        .to raise_error(Hipparchus::UnsupportedDatabase, /Mysql2/)
    end

    it "routes PostgreSQL connections to the PostgreSQL extractor" do
      connection = Struct.new(:adapter_name).new("PostgreSQL")

      extractor = Hipparchus::Extractor.for(connection, Object.new)
      expect(extractor).to be_a(Hipparchus::Extractor::PostgreSQL)
    end
  end
end
