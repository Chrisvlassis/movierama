### --------------------------------------------------------- ###
### -------------------- STREAMING -------------------------- ###
### --------------------------------------------------------- ###
# Spark Structured Streaming job for MovieRama.
# Simulates real-time ratings feed by watching a folder.
# When a new ratings file appears it processes it immediately.

# Since this is extra i will keep it very simple. We could add a lot more validation and transformations here.
#
# Flow:
#   Watch data/streaming/incoming/ for new CSV files
#         ↓
#   Validate each incoming rating
#         ↓
#   Append valid records to output file

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import StructType, StructField, IntegerType, FloatType, StringType


# streaming requires  schema. So, i must create one
RATINGS_SCHEMA = StructType([
    StructField("user_id",   IntegerType(), nullable=True),
    StructField("movie_id",  IntegerType(), nullable=True),
    StructField("rating",    FloatType(),   nullable=True),
    StructField("timestamp", StringType(),  nullable=True),
])
### -------------------------------------------------------- ###
# SPARK SESSION
### -------------------------------------------------------- ###
def create_spark_session():
    return SparkSession.builder \
        .appName("MovieRama Streaming") \
        .master("local[*]") \
        .config("spark.sql.shuffle.partitions", "4") \
        .getOrCreate()


### -------------------------------------------------------- ###
# VALIDATE
### -------------------------------------------------------- ###
def validate(df):
    """
    Validates incoming ratings.
    Drops invalid records silently.

    Rules:
        - user_id must not be null
        - movie_id must not be null
        - rating must be between 0 and 5
    """
    return df.filter(
        F.col("user_id").isNotNull() &
        F.col("movie_id").isNotNull() &
        F.col("rating").isNotNull() &
        F.col("rating").between(0, 5)
    )


### -------------------------------------------------------- ###
# MAIN
### -------------------------------------------------------- ###
def main():

    print("[STREAMING] Starting MovieRama Streaming Pipeline...")

    # paths
    incoming_path = "/data/streaming/incoming"
    output_path   = "/data/streaming/output"
    checkpoint    = "/data/streaming/checkpoint"

    # create spark session
    spark = create_spark_session()
    spark.sparkContext.setLogLevel("WARN")

    print(f"[STREAMING] Watching {incoming_path} for new files...")

    # ------------------------------------------------- #
    # READ STREAM
    # Watch the incoming folder for new CSV files.
    # ------------------------------------------------- #
    # watch the incoming folder for new CSV files
    # every 10 seconds Spark checks if a new file appeared
    # maxFilesPerTrigger=1 means process one file at a time as they arrive
    raw_stream = spark.readStream \
        .option("header", "true") \
        .schema(RATINGS_SCHEMA) \
        .option("maxFilesPerTrigger", 1) \
        .csv(incoming_path)

    # ------------------------------------------------- #
    # VALIDATE
    # ------------------------------------------------- #
    valid_df = validate(raw_stream)

    # ------------------------------------------------- #
    # WRITE STREAM
    # Append valid records directly to output.
    # No transformation - data inserted as is.
    # ------------------------------------------------- #
    # append mode: new records are added to existing output
    # checkpointLocation: tracks which files were already processed
    # if pipeline crashes and restarts, it won't reprocess old files
    # trigger every 10 seconds: check for new files and process them
    query = valid_df.writeStream \
        .outputMode("append") \
        .format("parquet") \
        .option("path", output_path) \
        .option("checkpointLocation", checkpoint) \
        .trigger(processingTime="10 seconds") \
        .start()

        

    print("[STREAMING] Pipeline running! Waiting for new files...")
    print(f"[STREAMING] Drop new CSV files into {incoming_path} to trigger processing")

    # keep running until manually stopped
    query.awaitTermination()


if __name__ == "__main__":
    main()