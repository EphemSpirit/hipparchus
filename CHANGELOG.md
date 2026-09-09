## [Unreleased]

- Schema extraction: `Hipparchus.extract` reads a live database into a
  database-agnostic intermediate representation (`Hipparchus::IR::Schema`).
  The caller supplies an ActiveRecord connection and the underlying raw driver
  connection; each extractor exposes a single `#call` method. PostgreSQL is the
  first supported adapter (tables, columns, comments, composite primary and
  foreign keys, referential actions, indexes).

## [0.1.0] - 2026-09-06

- Initial release
