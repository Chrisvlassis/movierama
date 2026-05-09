
### -------------------------------------------------------- ###
# Record level validation.
# Validates each record field by field against expected types.
# Bad records go to failed with the reason why they failed.


# (if there was more time i would have used more parameters in order no to make this so long!)
# We could also, add a mechanism to 'resend' the data that was 'corrupted'
### -------------------------------------------------------- ###

from pyspark.sql import functions as F
from pyspark.sql.types import IntegerType, FloatType
from pyspark.sql.types import StringType



def validate_and_split(df, schema, dataset_name):
    """
    Validates each record field by field.

    Inputs: 
    df - the dataframe to validate. (Spark DataFrame)
    schema - dictionary defining expected type for each column
                       example:
                       {
                           "movie_id": "integer",
                           "title":    "string",
                           "genre":    "string",
                       }
    dataset_name - the name of the dataset. (String)

    Returns (valid_df, failed_df).
    valid_df  - clean records with correct types
    failed_df - bad records with reason why they failed
    """

    # ------------------------------------------------- #
    # REMOVE EXACT DUPLICATES
    # Drop rows that are completely identical.
    # Keep one copy, remove the rest.
    # ------------------------------------------------- #
    before_count = df.count()
    df = df.dropDuplicates()
    after_count = df.count()
    duplicates_removed = before_count - after_count

    if duplicates_removed > 0:
        print(f"[VALIDATION] {dataset_name}: removed {duplicates_removed} exact duplicate rows")


    # start with all records marked as valid. This is a boolean column that will be used to mark if the record is valid or not.
    df = df.withColumn("_is_valid", F.lit(True))
    df = df.withColumn("_invalid_reason", F.lit(""))

    # validate each column based on expected type
    for col_name, expected_type in schema.items():

        if expected_type == "integer":
            # try casting to integer - if it fails Spark returns null
            df = df.withColumn(
                "_is_valid",
                F.when(
                    F.col(col_name).isNotNull() & # check if the column is not null
                    F.col(col_name).cast(IntegerType()).isNull(), # cast the column to integer and check if it is null
                    F.lit(False) # Then set the _is_valid column to false
                ).otherwise(F.col("_is_valid")) # Otherwise keep the current value of _is_valid

            ).withColumn(
                "_invalid_reason",
                F.when(
                    F.col(col_name).isNotNull() &
                    F.col(col_name).cast(IntegerType()).isNull(),
                    F.concat(F.col("_invalid_reason"),
                             F.lit(f"{col_name} is not an integer; "))
                ).otherwise(F.col("_invalid_reason"))
            )

        elif expected_type == "float":
            # try casting to float - if it fails Spark returns null
            df = df.withColumn(
                "_is_valid",
                F.when(
                    F.col(col_name).isNotNull() &
                    F.col(col_name).cast(FloatType()).isNull(),
                    F.lit(False)
                ).otherwise(F.col("_is_valid"))
            ).withColumn(
                "_invalid_reason",
                F.when(
                    F.col(col_name).isNotNull() &
                    F.col(col_name).cast(FloatType()).isNull(),
                    F.concat(F.col("_invalid_reason"),
                             F.lit(f"{col_name} is not a float; "))
                ).otherwise(F.col("_invalid_reason"))
            )

        elif expected_type == "date":
            # try casting to date - if it fails Spark returns null
            df = df.withColumn(
                "_is_valid",
                F.when(
                    F.col(col_name).isNotNull() &
                    F.to_date(F.col(col_name)).isNull(),
                    F.lit(False)
                ).otherwise(F.col("_is_valid"))
            ).withColumn(
                "_invalid_reason",
                F.when(
                    F.col(col_name).isNotNull() &
                    F.to_date(F.col(col_name)).isNull(),
                    F.concat(F.col("_invalid_reason"),
                             F.lit(f"{col_name} is not a valid date; "))
                ).otherwise(F.col("_invalid_reason"))
            )

        elif expected_type == "timestamp":
            # try casting to timestamp - if it fails Spark returns null
            df = df.withColumn(
                "_is_valid",
                F.when(
                    F.col(col_name).isNotNull() &
                    F.to_timestamp(F.col(col_name)).isNull(),
                    F.lit(False)
                ).otherwise(F.col("_is_valid"))
            ).withColumn(
                "_invalid_reason",
                F.when(
                    F.col(col_name).isNotNull() &
                    F.to_timestamp(F.col(col_name)).isNull(),
                    F.concat(F.col("_invalid_reason"),
                             F.lit(f"{col_name} is not a valid timestamp; "))
                ).otherwise(F.col("_invalid_reason"))
            )

    # split into valid and failed

    # keep only records where _is_valid is True
    valid_df = df.filter(F.col("_is_valid") == True)

    # keep only records where _is_valid is False
    failed_df = df.filter(F.col("_is_valid") == False)

    # drop the internal tracking columns
    # we don't need them anymore after the split
    valid_df      = valid_df.drop("_is_valid", "_invalid_reason")
    failed_df = failed_df.drop("_is_valid")

    # log counts
    valid_count     = valid_df.count()
    failed_count = failed_df.count()

    print(f"[VALIDATION] {dataset_name}: {valid_count} valid, {failed_count} failedd")

    return valid_df, failed_df



# --------------------------------------------------------- #
# SCHEMA EVOLUTION
# Handle new or missing columns.
# --------------------------------------------------------- #

def handle_schema_evolution(df, expected_columns, dataset_name):
    """
    Handles schema evolution.

    Inputs:
        df               - raw Spark DataFrame
        expected_columns - list of columns we expect
                           example: ["movie_id", "title", "genre"]
        dataset_name     - name of dataset for logging
                           example: "movies"

    Behaviour:
        new column appears   - log warning, ignore it
        column goes missing  - log warning, fills them with null
    """

    actual_columns = df.columns

    # check for new columns we dont know about
    new_columns = set(actual_columns) - set(expected_columns)
    if new_columns:
        print(f"[SCHEMA EVOLUTION] {dataset_name}: new columns detected: {new_columns}")
        print(f"[SCHEMA EVOLUTION] {dataset_name}: these columns will be ignored")

    # check for missing columns we expect
    missing_columns = set(expected_columns) - set(actual_columns)
    if missing_columns:
        print(f"[SCHEMA EVOLUTION] {dataset_name}: missing columns: {missing_columns}")
        print(f"[SCHEMA EVOLUTION] {dataset_name}: missing columns will be filled with null")
        for col in missing_columns:
            df = df.withColumn(col, F.lit(None).cast(StringType())) # Make the values of the missing columns null. 

    # only keep the columns we know about
    return df.select(expected_columns)