### --------------------------------------------------------- ###
### ------------------------- LOAD -------------------------- ###
### --------------------------------------------------------- ###
# Writes transformed data to disk as Parquet files.
# Also writes failed records to a separate invalid folder.

def load(ratings_per_movie_df, ratings_per_genre_df, movies_failed_df, ratings_failed_df, output_path):
    """
    Writes all DataFrames to disk.

    Inputs:
        ratings_per_movie_df  - enriched movie data from transform
        ratings_per_genre_df  - enriched genre data from transform
        movies_failed_df      - invalid movie records from extract
        ratings_failed_df     - invalid ratings records from extract
        output_path           - base path to write output
                                example: "/data/output"

    Output structure:
        /data/output/
        ├── ratings_per_movie/   ← enriched movie data
        ├── ratings_per_genre/   ← enriched genre data
        └── invalid/
            ├── movies/          ← invalid movie records
            └── ratings/         ← invalid rating records
    """

    # ------------------------------------------------- #
    # WRITE VALID DATA (the aggregated ones)
    # ------------------------------------------------- #

    print(f"[LOAD] Writing ratings_per_movie to {output_path}/ratings_per_movie")
    ratings_per_movie_df.write \
        .mode("overwrite") \
        .parquet(f"{output_path}/ratings_per_movie")
    print(f"[LOAD] ratings_per_movie written successfully")

    print(f"[LOAD] Writing ratings_per_genre to {output_path}/ratings_per_genre")
    ratings_per_genre_df.write \
        .mode("overwrite") \
        .parquet(f"{output_path}/ratings_per_genre")
    print(f"[LOAD] ratings_per_genre written successfully")

    # ------------------------------------------------- #
    # WRITE invalid DATA
    # Only write if there are failed records
    # ------------------------------------------------- #

    movies_failed_count  = movies_failed_df.count()
    ratings_failed_count = ratings_failed_df.count()

    if movies_failed_count > 0:
        print(f"[LOAD] Writing {movies_failed_count} failed movies to invalid")
        movies_failed_df.write \
            .mode("overwrite") \
            .parquet(f"{output_path}/invalid/movies")
        print(f"[LOAD] Failed movies written to invalid")
    else:
        print(f"[LOAD] No failed movies to invalid")

    if ratings_failed_count > 0:
        print(f"[LOAD] Writing {ratings_failed_count} failed ratings to invalid")
        ratings_failed_df.write \
            .mode("overwrite") \
            .parquet(f"{output_path}/invalid/ratings")
        print(f"[LOAD] Failed ratings written to invalid")
    else:
        print(f"[LOAD] No failed ratings to invalid")

    print(f"[LOAD] Done! All data written to {output_path}")