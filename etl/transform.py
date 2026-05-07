### --------------------------------------------------------- ###
### ---------------------- TRANSFORM ------------------------ ###
### --------------------------------------------------------- ###
# Transforms the extracted data using SparkSQL.
# Joins movies with ratings and calculates statistics.
# Adds derived columns like popularity and genre rank.
#(we could use here a spark dataframe api to do the transformations instead of using sql -> so, faster, more efficient and more parametrized)

from pyspark.sql import functions as F


def transform(spark, movies_df, ratings_df):
    """
    Transforms movies and ratings DataFrames using SparkSQL.

    Inputs:
        spark      - active SparkSession
        movies_df  - valid movies DataFrame from extract
                     columns: movie_id, title, genre, release_date, cast
        ratings_df - valid ratings DataFrame from extract
                     columns: user_id, movie_id, rating, timestamp

    Returns:
        ratings_per_movie_df - transformed DataFrame ready to load

        ratings_per_genre_df - transformed DataFrame ready to load

    """

    print("[TRANSFORM] Starting transformations...")

    # register DataFrames as SQL tables
    # this allows us to query them using SparkSQL
    movies_df.createOrReplaceTempView("movies")
    ratings_df.createOrReplaceTempView("ratings")

    # ------------------------------------------------- #
    # MAIN TRANSFORMATION 1 -> ratings_per_movie_df
    # ------------------------------------------------- #
    ratings_per_movie_df = spark.sql("""
        SELECT
            m.movie_id,
            m.title,
            -- average rating per movie rounded to 2 decimal places
            ROUND(AVG(r.rating), 2) AS avg_rating,
            -- total number of ratings per movie
            COUNT(r.rating) AS total_ratings
        FROM movies m
        -- LEFT JOIN keeps all movies even if they have no ratings
        LEFT JOIN ratings r ON m.movie_id = r.movie_id
        GROUP BY
            m.movie_id,
            m.title
    """)

    # ------------------------------------------------- #
    # MAIN TRANSFORMATION 2 -> ratings_per_genre_df
    # ------------------------------------------------- #
    ratings_per_genre_df = spark.sql("""
        SELECT
            m.genre,
            -- average rating per genre rounded to 2 decimal places
            ROUND(AVG(r.rating), 2) AS avg_rating,
            -- total number of ratings per genre
            COUNT(r.rating) AS total_ratings
        FROM movies m
        -- LEFT JOIN keeps all movies even if they have no ratings
        LEFT JOIN ratings r ON m.movie_id = r.movie_id
        GROUP BY
            m.genre
    """)

    # ------------------------------------------------- #
    # DERIVED COLUMNS 1  -> ratings_per_movie_df
    # Add extra columns based on the transformed data
    # ------------------------------------------------- #

    # add popularity category based on total ratings
    ratings_per_movie_df = ratings_per_movie_df.withColumn(
        "popularity",
        F.when(F.col("total_ratings") >= 5, "popular")    # 5+ ratings
         .when(F.col("total_ratings") >= 3, "moderate")   # 3-4 ratings
         .otherwise("limited")                            # less than 3
    )

    # add pipeline run timestamp. Important as techinical column. 
    # useful for tracking when this data was processed
    ratings_per_movie_df = ratings_per_movie_df.withColumn(
        "processed_at",
        F.current_timestamp()
    )

    print("[TRANSFORM] Transformations complete!")
    print("[TRANSFORM] Sample output:")
    ratings_per_movie_df.show(5, truncate=False)

    # ------------------------------------------------- #
    # DERIVED COLUMNS  2  -> ratings_per_genre_df
    # Add extra columns based on the transformed data
    # ------------------------------------------------- #

    # add popularity category based on total ratings
    ratings_per_genre_df = ratings_per_genre_df.withColumn(
        "popularity",
        F.when(F.col("total_ratings") >= 5, "popular")    # 5+ ratings
         .when(F.col("total_ratings") >= 3, "moderate")   # 3-4 ratings
         .otherwise("limited")                            # less than 3
    )

    # add pipeline run timestamp. Important as techinical column. 
    # useful for tracking when this data was processed
    ratings_per_genre_df = ratings_per_genre_df.withColumn(
        "processed_at",
        F.current_timestamp()
    )

    print("[TRANSFORM] Transformations complete!")
    print("[TRANSFORM] Sample output:")
    ratings_per_genre_df.show(5, truncate=False)


    return ratings_per_movie_df, ratings_per_genre_df