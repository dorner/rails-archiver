# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## UNRELEASED

# [0.3.0] - 2025-05-22
- Added retries for delete table operations to handle SQL Timeouts and deadlocks.

# [0.2.0] - 2025-01-20
- Added support for enum columns - should be able to handle both keys and values.
- Refactored the `unarchiver` method to more easily subclass `Unarchiver`.
- For `belongs_to` associations, replace foreign key attributes with actual reference to the relevant object while archiving to avoid issues with validation.
