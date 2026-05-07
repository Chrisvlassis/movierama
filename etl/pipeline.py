### --------------------------------------------------------- ###
### ---------------------- PIPELINE ------------------------- ###
### --------------------------------------------------------- ###
# Main entry point for the MovieRama ETL pipeline.
# Ties together extract, transform and load.
#
# Flow:
#   Extract  - read movies.csv + ratings.csv (inside here we also run the validation)
#   Transform - join, aggregate, enrich with SparkSQL
#   Load     - write results to parquet + quarantine

from pyspark.sql import SparkSession
from extract import extract, MOVIES_SCHEMA, RATINGS_SCHEMA
from transform import transform
from load import load


### -------------------------------------------------------- ###
# SPARK SESSION
# Entry point for everything Spark.
# Local mode means Spark runs on this single machine.
# In production this would point to a real Spark cluster.
### -------------------------------------------------------- ###
def create_spark_session():
    return SparkSession.builder \
        .appName("MovieRama ETL Pipeline") \
        .master("local[*]") \
        .config("spark.sql.shuffle.partitions", "4") \
        .getOrCreate()


### -------------------------------------------------------- ###
# MAIN
### -------------------------------------------------------- ###
def main():

    print("[PIPELINE] Starting MovieRama ETL Pipeline...")

    # ------------------------------------------------- #
    # PATHS
    # ------------------------------------------------- #
    movies_path  = "/data/movies.csv"
    ratings_path = "/data/ratings.csv"
    output_path  = "/data/output"

    # ------------------------------------------------- #
    # SPARK SESSION
    # ------------------------------------------------- #
    spark = create_spark_session()
    print("[PIPELINE] Spark session created")

    # ------------------------------------------------- #
    # EXTRACT
    # reads CSVs, validates records, splits valid/failed
    # ------------------------------------------------- #
    print("[PIPELINE] Starting extract...")
    movies_valid,  movies_failed  = extract(spark, movies_path,  MOVIES_SCHEMA,  "movies")
    ratings_valid, ratings_failed = extract(spark, ratings_path, RATINGS_SCHEMA, "ratings")

    # ------------------------------------------------- #
    # TRANSFORM
    # joins movies + ratings, calculates statistics
    # ------------------------------------------------- #
    print("[PIPELINE] Starting transform...")
    ratings_per_movie_df, ratings_per_genre_df = transform(spark, movies_valid, ratings_valid)

    # ------------------------------------------------- #
    # LOAD
    # writes results to parquet + failed to quarantine
    # ------------------------------------------------- #
    print("[PIPELINE] Starting load...")
    load(
        ratings_per_movie_df,
        ratings_per_genre_df,
        movies_failed,
        ratings_failed,
        output_path
    )

    print("[PIPELINE] MovieRama ETL Pipeline complete!")
    spark.stop()


if __name__ == "__main__":
    main()