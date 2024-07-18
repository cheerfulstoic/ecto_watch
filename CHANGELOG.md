# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.4] - 2023-07-18

### Fixed

- Backwards compatibility with older versions of postgres that don't support the `OR REPLACE` clause in `CREATE TRIGGER` (thanks @adampash / #10)

## [0.5.1] - 2023-07-02

### Fixed

- Use quotes around table name in trigger to allow for special characters

## [0.5.0] - 2023-07-02

### Fixed

- Support for ecto's `@schema_prefix`

