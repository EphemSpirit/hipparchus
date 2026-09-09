# frozen_string_literal: true

require_relative "hipparchus/version"
require_relative "hipparchus/ir"
require_relative "hipparchus/extractor"
require_relative "hipparchus/extractor/base"
require_relative "hipparchus/extractor/postgresql"

# Hipparchus builds Entity Relationship Diagrams from a live relational database.
#
# Step one is schema extraction: given the caller's own connections, produce a
# database-agnostic intermediate representation ({Hipparchus::IR::Schema}) that
# later stages lay out and render.
module Hipparchus
  # Base class for all Hipparchus errors.
  class Error < StandardError; end

  # Raised when no extractor is registered for a connection's adapter.
  class UnsupportedDatabase < Error; end

  # Extract the schema of a database into the intermediate representation.
  #
  # The caller owns both connections; Hipparchus never opens or closes one.
  #
  # @param connection [Object] an ActiveRecord connection (adapter identity + metadata)
  # @param raw_connection [Object] the underlying driver connection (catalog queries)
  # @return [Hipparchus::IR::Schema]
  # @raise [Hipparchus::UnsupportedDatabase] if the adapter is not supported
  #
  # @example
  #   conn = ActiveRecord::Base.connection
  #   Hipparchus.extract(connection: conn, raw_connection: conn.raw_connection)
  def self.extract(connection:, raw_connection:)
    Extractor.call(connection: connection, raw_connection: raw_connection)
  end
end
