# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

**IMPORTANT NOTE**: Make sure to see the [Upgrading Versions](guides/howtos/Upgrading Versions.md) guide in the [HexDocs documentation](https://hexdocs.pm/ecto_watch) if you're having an issue after upgrading.

## [0.9.11] - 2023-08-12

### Fixed

- Allow empty `trigger_columns` and `extra_columns` options (#24 / thanks @barrelltech)

## [0.9.10] - 2023-08-12

### Fixed

- Non-EctoWatch function were being reported as needing to be cleaned up (#23 / thanks @barrelltech / @adampash)
- Function / trigger cleanup was still looking for `ECTO_WATCH_CLEANUP_TRIGGERS` environment variable when `ECTO_WATCH_CLEANUP` was the documented option (#23 / thanks @barrelltech / @adampash)

## [0.9.9] - 2023-08-10

### Added

- Documentation release

## [0.9.8] - 2023-08-10

### Added

- Documentation release

## [0.9.7] - 2023-08-10

### Added

- Documentation release

## [0.9.6] - 2023-08-10

### Added

- Documentation release

## [0.9.5] - 2023-08-08

### Added

- Add validation errors for when watchers are created which can't be disambiguated

## [0.9.4] - 2023-08-08

### Fixed

- Documentation release

## [0.9.3] - 2023-08-08

### Fixed

- Documentation release

## [0.9.2] - 2023-08-08

### Fixed

- Documentation release

## [0.9.1] - 2023-08-08

### Fixed

- Documentation release

## [0.9.0] - 2023-08-07

### Added

- Warnings when there are extra triggers / function in the database
- Support for auto-deleting triggers and functions when the `ECTO_WATCH_CLEANUP` environment variable is set to `cleanup`

## [0.8.1] - 2023-08-07

### Fixed

- Add detail to exception for more helpful info on the change in messages

## [0.8.0] - 2023-08-07

### Changed

- BREAKING: Don't require specifying update type for watchers with labels (#19)

### Added

- Allow watchers without an ecto schema (thanks @frerich / #18)

## [0.7.0] - 2023-07-31

### Changed

- Allow empty watcher list (thanks @barrelltech / #14)

## [0.6.0] - 2023-07-30

### Added

- Support for subscribing to association column values (thanks @barrelltech / #6)

### Changed

- Changed broadcast messages from a 4-element tuple to a 3-element tuple (see #12 / thanks @venkatd + @barrelltech)

## [0.5.4] - 2023-07-18

### Fixed

- Backwards compatibility with older versions of postgres that don't support the `OR REPLACE` clause in `CREATE TRIGGER` (thanks @adampash / #10)

## [0.5.3] - 2023-07-12

### Fixed

- Support primary keys other than `id` (thanks @venkatd / #3)

## [0.5.1] - 2023-07-02

### Fixed

- Use quotes around table name in trigger to allow for special characters

## [0.5.0] - 2023-07-02

### Fixed

- Support for ecto's `@schema_prefix`

