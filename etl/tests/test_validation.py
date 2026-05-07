### --------------------------------------------------------- ###
### ------------------ TEST VALIDATION ---------------------- ###
### --------------------------------------------------------- ###
# Unit tests for validation.py
# Designed to achieve 100% code coverage of:
#   - validate_and_split()
#   - handle_schema_evolution()

import pytest
from pyspark.sql import SparkSession
from pyspark.sql.types import StructType, StructField, StringType

import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from validation import validate_and_split, handle_schema_evolution


# --------------------------------------------------------- #
# SPARK SESSION
# --------------------------------------------------------- #
@pytest.fixture(scope="session")
def spark():
    """
    Creates a single SparkSession shared across all tests.
    scope="session" means created once and reused.
    """
    return SparkSession.builder \
        .appName("MovieRama Validation Tests") \
        .master("local[2]") \
        .getOrCreate()


# --------------------------------------------------------- #
# SCHEMAS
# All columns are strings - same as our pipeline
# --------------------------------------------------------- #
FULL_SCHEMA = {
    "movie_id":     "integer",
    "rating":       "float",
    "release_date": "date",
    "timestamp":    "timestamp",
    "title":        "string",
}

STRING_SCHEMA = StructType([
    StructField("movie_id",     StringType(), True),
    StructField("rating",       StringType(), True),
    StructField("release_date", StringType(), True),
    StructField("timestamp",    StringType(), True),
    StructField("title",        StringType(), True),
])


# --------------------------------------------------------- #
# validate_and_split() TESTS
# --------------------------------------------------------- #

def test_valid_record_passes(spark):
    """
    Covers: valid path through all type checks.
    All fields valid → record passes through.
    """
    data = [("1", "4.5", "2010-07-16", "2024-01-01 10:00:00", "Inception")]
    df = spark.createDataFrame(data, schema=STRING_SCHEMA)

    valid_df, failed_df = validate_and_split(df, FULL_SCHEMA, "test")

    assert valid_df.count() == 1
    assert failed_df.count() == 0


def test_invalid_integer_quarantined(spark):
    """
    Covers: integer branch in validate_and_split.
    movie_id="abc" → not an integer → quarantined.
    """
    data = [("abc", "4.5", "2010-07-16", "2024-01-01 10:00:00", "Inception")]
    df = spark.createDataFrame(data, schema=STRING_SCHEMA)

    valid_df, failed_df = validate_and_split(df, FULL_SCHEMA, "test")

    assert valid_df.count() == 0
    assert failed_df.count() == 1

    reason = failed_df.select("_invalid_reason").collect()[0][0]
    assert "movie_id is not an integer" in reason


def test_invalid_float_quarantined(spark):
    """
    Covers: float branch in validate_and_split.
    rating="abc" → not a float → quarantined.
    """
    data = [("1", "abc", "2010-07-16", "2024-01-01 10:00:00", "Inception")]
    df = spark.createDataFrame(data, schema=STRING_SCHEMA)

    valid_df, failed_df = validate_and_split(df, FULL_SCHEMA, "test")

    assert valid_df.count() == 0
    assert failed_df.count() == 1

    reason = failed_df.select("_invalid_reason").collect()[0][0]
    assert "rating is not a float" in reason


def test_invalid_date_quarantined(spark):
    """
    Covers: date branch in validate_and_split.
    release_date="not-a-date" → not a valid date → quarantined.
    """
    data = [("1", "4.5", "not-a-date", "2024-01-01 10:00:00", "Inception")]
    df = spark.createDataFrame(data, schema=STRING_SCHEMA)

    valid_df, failed_df = validate_and_split(df, FULL_SCHEMA, "test")

    assert valid_df.count() == 0
    assert failed_df.count() == 1

    reason = failed_df.select("_invalid_reason").collect()[0][0]
    assert "release_date is not a valid date" in reason


def test_invalid_timestamp_quarantined(spark):
    """
    Covers: timestamp branch in validate_and_split.
    timestamp="not-a-timestamp" → not valid → quarantined.
    """
    data = [("1", "4.5", "2010-07-16", "not-a-timestamp", "Inception")]
    df = spark.createDataFrame(data, schema=STRING_SCHEMA)

    valid_df, failed_df = validate_and_split(df, FULL_SCHEMA, "test")

    assert valid_df.count() == 0
    assert failed_df.count() == 1

    reason = failed_df.select("_invalid_reason").collect()[0][0]
    assert "timestamp is not a valid timestamp" in reason


def test_null_values_pass(spark):
    """
    Covers: isNotNull() check - null values skip type validation.
    All nulls → valid because we only check type if value exists.
    """
    data = [(None, None, None, None, None)]
    df = spark.createDataFrame(data, schema=STRING_SCHEMA)

    valid_df, failed_df = validate_and_split(df, FULL_SCHEMA, "test")

    assert valid_df.count() == 1
    assert failed_df.count() == 0


def test_multiple_invalid_fields(spark):
    """
    Covers: multiple problems accumulated in _invalid_reason.
    Both movie_id and rating invalid → both appear in reason.
    """
    data = [("abc", "xyz", "2010-07-16", "2024-01-01 10:00:00", "Inception")]
    df = spark.createDataFrame(data, schema=STRING_SCHEMA)

    valid_df, failed_df = validate_and_split(df, FULL_SCHEMA, "test")

    assert valid_df.count() == 0
    assert failed_df.count() == 1

    reason = failed_df.select("_invalid_reason").collect()[0][0]
    assert "movie_id is not an integer" in reason
    assert "rating is not a float" in reason


def test_empty_dataframe(spark):
    """
    Covers: empty DataFrame edge case.
    No records → both valid and failed are empty.
    """
    df = spark.createDataFrame([], schema=STRING_SCHEMA)

    valid_df, failed_df = validate_and_split(df, FULL_SCHEMA, "test")

    assert valid_df.count() == 0
    assert failed_df.count() == 0


# --------------------------------------------------------- #
# handle_schema_evolution() TESTS
# --------------------------------------------------------- #

def test_new_column_ignored(spark):
    """
    Covers: new columns detected branch.
    Extra column appears → logged and ignored.
    """
    # DataFrame has an extra "budget" column
    schema_with_extra = StructType([
        StructField("movie_id", StringType(), True),
        StructField("title",    StringType(), True),
        StructField("budget",   StringType(), True),  # extra!
    ])

    data = [("1", "Inception", "1000000")]
    df = spark.createDataFrame(data, schema=schema_with_extra)

    expected_columns = ["movie_id", "title"]
    result_df = handle_schema_evolution(df, expected_columns, "test")

    # budget column should be gone
    assert "budget" not in result_df.columns
    assert result_df.count() == 1


def test_missing_column_filled_with_null(spark):
    """
    Covers: missing columns branch.
    Expected column missing → filled with null.
    """
    # DataFrame is missing "genre" column
    schema_without_genre = StructType([
        StructField("movie_id", StringType(), True),
        StructField("title",    StringType(), True),
    ])

    data = [("1", "Inception")]
    df = spark.createDataFrame(data, schema=schema_without_genre)

    expected_columns = ["movie_id", "title", "genre"]
    result_df = handle_schema_evolution(df, expected_columns, "test")

    # genre column should exist and be null
    assert "genre" in result_df.columns
    genre_value = result_df.select("genre").collect()[0][0]
    assert genre_value is None


def test_no_schema_changes(spark):
    """
    Covers: no changes needed path.
    Exact columns match → no warnings, no changes.
    """
    data = [("1", "Inception")]
    schema = StructType([
        StructField("movie_id", StringType(), True),
        StructField("title",    StringType(), True),
    ])
    df = spark.createDataFrame(data, schema=schema)

    expected_columns = ["movie_id", "title"]
    result_df = handle_schema_evolution(df, expected_columns, "test")

    assert result_df.columns == expected_columns
    assert result_df.count() == 1