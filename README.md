# Hipparchus

Hipparchus generates Entity Relationship Diagrams from a live relational
database. It works in stages; the first is **schema extraction**, which reads the
database catalog and produces a small, database-agnostic **intermediate
representation (IR)** that later stages lay out and render.

## Installation

Add the gem to your application's Gemfile:

```ruby
gem "hipparchus"
```

Then run `bundle install`.

## Usage

You hand Hipparchus two connections and it never opens or closes one itself:

- an **ActiveRecord connection**, used to identify the adapter and read the
  database name;
- the **raw driver connection** (e.g. `PG::Connection`), used to run catalog
  queries directly, so you stay in control of the session those queries run in.

```ruby
require "active_record"
require "hipparchus"

ActiveRecord::Base.establish_connection(ENV["DATABASE_URL"])
connection = ActiveRecord::Base.connection

schema = Hipparchus.extract(
  connection: connection,
  raw_connection: connection.raw_connection
)

schema.tables.each do |table|
  puts table.qualified_name
  table.foreign_keys.each do |fk|
    puts "  #{fk.columns.join(', ')} -> #{fk.qualified_to} (#{fk.primary_key.join(', ')})"
  end
end
```

### The intermediate representation

`Hipparchus::IR` holds immutable value objects:

| Object       | Notable fields                                                             |
| ------------ | ------------------------------------------------------------------------- |
| `Schema`     | `adapter`, `database`, `tables`, `extracted_at`                          |
| `Table`      | `name`, `schema`, `comment`, `columns`, `primary_key`, `foreign_keys`, `indexes` |
| `Column`     | `name`, `type` (normalized), `sql_type` (raw), `null`, `default`, `primary_key`, `comment`, `position` |
| `ForeignKey` | `columns`, `to_table`, `to_schema`, `primary_key`, `on_delete`, `on_update` |
| `Index`      | `name`, `columns`, `unique`, `using`, `where`                            |

`primary_key`, and a foreign key's `columns` / `primary_key`, are ordered arrays,
so composite keys are represented faithfully.

### The extractor interface

Each extractor is constructed with the two connections and exposes exactly one
method, `#call`, returning a `Hipparchus::IR::Schema`:

```ruby
Hipparchus::Extractor.for(connection, connection.raw_connection).call
```

`Hipparchus::Extractor.for` raises `Hipparchus::UnsupportedDatabase` for an
adapter that has no extractor yet. PostgreSQL is currently the only one
implemented.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then run
`bundle exec rspec` to run the tests and `bundle exec rubocop` to lint.

The PostgreSQL extractor spec needs a database. Point it at one with
`HIPPARCHUS_TEST_DATABASE_URL` (e.g.
`postgres://postgres:postgres@localhost:5432/postgres`); without it that spec
skips itself.

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/EphemSpirit/hipparchus.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
