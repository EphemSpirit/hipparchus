# frozen_string_literal: true

module Hipparchus
  # Picks the right concrete extractor for a connection and drives it.
  #
  # Every concrete extractor exposes a single method, +#call+, which returns a
  # {Hipparchus::IR::Schema}. Callers hand in two connections:
  #
  # * +connection+     - an ActiveRecord connection, used only to identify the
  #   adapter and read database-level metadata.
  # * +raw_connection+ - the underlying driver connection (e.g. +PG::Connection+),
  #   used to run catalog queries directly.
  module Extractor
    REGISTRY = { "postgresql" => :PostgreSQL }.freeze

    # Extract in one call.
    #
    # @param connection [Object] an ActiveRecord connection
    # @param raw_connection [Object] the underlying driver connection
    # @return [Hipparchus::IR::Schema]
    def self.call(connection:, raw_connection:)
      self.for(connection, raw_connection).call
    end

    # Build (but do not run) the extractor for a connection.
    #
    # @param connection [Object] an ActiveRecord connection
    # @param raw_connection [Object] the underlying driver connection
    # @return [#call] an extractor whose +#call+ returns a {Hipparchus::IR::Schema}
    # @raise [Hipparchus::UnsupportedDatabase] if no extractor is registered
    def self.for(connection, raw_connection)
      key = connection.adapter_name.to_s.downcase
      const = REGISTRY.fetch(key) do
        raise Hipparchus::UnsupportedDatabase,
              "no schema extractor for adapter #{connection.adapter_name.inspect}"
      end
      const_get(const).new(connection, raw_connection)
    end
  end
end
