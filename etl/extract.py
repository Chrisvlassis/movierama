### --------------------------------------------------------- ###
### ------------------------ EXTRACT ------------------------ ###
### --------------------------------------------------------- ###
# Reads raw CSV files into Spark DataFrames.
# All columns are read as strings first - no type assumptions.
# Then schema evolution is handled and validation is called.

from pyspark.sql import functions as F
from validation import validate_and_split, handle_schema_evolution


# --------------------------------------------------------- #
# EXPECTED SCHEMAS
# Define expected columns and their target types.
# We read everything as string first, then validate and cast.
# --------------------------------------------------------- #
MOVIES_SCHEMA = {
    "movie_id":     "integer",
    "title":        "string",
    "genre":        "string",
    "release_date": "date",
    "cast":         "string",
}

RATINGS_SCHEMA = {
    "user_id":   "integer",
    "movie_id":  "integer",
    "rating":    "float",
    "timestamp": "timestamp",
}



# --------------------------------------------------------- #
# CAST TO TYPES
# Cast validated columns to their correct types. (after validation !SOS!)
# Safe to do now because all records passed validation.
# --------------------------------------------------------- #

def cast_to_types(df, schema):
    """
    Casts each column to its correct type.
    Only called on valid records after validation.

    Inputs:
        df     - validated Spark DataFrame (all strings)
        schema - dictionary of column names and their types
                 example: {"movie_id": "integer", "rating": "float"}
    """
    from pyspark.sql.types import IntegerType, FloatType

    for col_name, expected_type in schema.items():
        if expected_type == "integer":
            df = df.withColumn(col_name, F.col(col_name).cast(IntegerType()))
        elif expected_type == "float":
            df = df.withColumn(col_name, F.col(col_name).cast(FloatType()))
        elif expected_type == "date":
            df = df.withColumn(col_name, F.to_date(F.col(col_name)))
        elif expected_type == "timestamp":
            df = df.withColumn(col_name, F.to_timestamp(F.col(col_name)))
    return df


# --------------------------------------------------------- #
# ----------------------- EXTRACT ------------------------- #
# --------------------------------------------------------- #

def extract(spark, path, schema, dataset_name):
    """
    Reads a CSV file into a Spark DataFrame.
    All columns read as strings first.
    Then validates and splits into valid + failed.

    Inputs:
        spark        - active SparkSession
        path         - path to CSV file
                       example: "/data/movies.csv"
        schema       - dictionary of expected columns and types
                       example: MOVIES_SCHEMA or RATINGS_SCHEMA
        dataset_name - name of dataset for logging
                       example: "movies" or "ratings"

    Returns:
        valid_df  - clean records ready for transform
        failed_df - invalid records with reason why they failed
    """

    print(f"[EXTRACT] Reading {dataset_name} from {path}")

    # read everything as strings first
    # then we validate and cast ourselves
    df = spark.read \
        .option("header", "true") \
        .option("inferSchema", "false") \
        .csv(path)

    print(f"[EXTRACT] {dataset_name} raw columns: {df.columns}")
    print(f"[EXTRACT] {dataset_name} raw count: {df.count()}")

    # handle schema evolution
    df = handle_schema_evolution(df, list(schema.keys()), dataset_name) # this is mainly informative!

    # validate records and split into valid and failed
    valid_df, failed_df = validate_and_split(df, schema, dataset_name)

    # cast valid records to correct types
    valid_df = cast_to_types(valid_df, schema)

    print(f"[EXTRACT] {dataset_name} valid count: {valid_df.count()}")

    return valid_df, failed_df