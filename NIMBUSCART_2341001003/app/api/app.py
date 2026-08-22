import os
import time
from decimal import Decimal, InvalidOperation

import psycopg2
from flask import Flask, jsonify, request
from psycopg2.extras import RealDictCursor

app = Flask(__name__)


@app.after_request
def add_cors_headers(response):
    response.headers["Access-Control-Allow-Origin"] = "http://localhost:8000"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    response.headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS"
    return response

DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ.get("DB_NAME", "nimbuscart")
DB_USER = os.environ.get("DB_USER", "nimbuscart")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")


def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=5,
    )


def initialize_database(max_attempts=1):
    last_error = None
    for attempt in range(max_attempts):
        try:
            with get_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        CREATE TABLE IF NOT EXISTS products (
                            id SERIAL PRIMARY KEY,
                            name VARCHAR(255) NOT NULL,
                            price NUMERIC(12, 2) NOT NULL CHECK (price >= 0),
                            stock INTEGER NOT NULL CHECK (stock >= 0)
                        )
                        """
                    )
                conn.commit()
            return
        except Exception as exc:
            last_error = exc
            if attempt + 1 < max_attempts:
                time.sleep(2)
    app.logger.warning("Database initialization did not complete at startup: %s", last_error)


@app.get("/health")
def health():
    return jsonify({"status": "ok"}), 200

@app.get("/api/items")
@app.get("/items")
def get_items():
    try:
        initialize_database(max_attempts=30)
        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT id, name, price, stock FROM products ORDER BY id")
                rows = cur.fetchall()
        for row in rows:
            row["price"] = float(row["price"])
        return jsonify(rows), 200
    except Exception as exc:
        app.logger.exception("Failed to fetch products")
        return jsonify({"error": "Database error", "details": str(exc)}), 500

@app.post("/api/items")
@app.post("/items")
def create_item():

    data = request.get_json(silent=True) or {}
    name = str(data.get("name", "")).strip()

    if not name:
        return jsonify({"error": "name is required"}), 400

    try:
        price = Decimal(str(data.get("price")))
        stock = int(data.get("stock"))
    except (InvalidOperation, TypeError, ValueError):
        return jsonify({"error": "price must be numeric and stock must be an integer"}), 400

    if price < 0 or stock < 0:
        return jsonify({"error": "price and stock must be non-negative"}), 400

    try:
        initialize_database(max_attempts=30)
        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "INSERT INTO products (name, price, stock) VALUES (%s, %s, %s) RETURNING id, name, price, stock",
                    (name, price, stock),
                )
                row = cur.fetchone()
            conn.commit()
        row["price"] = float(row["price"])
        return jsonify(row), 201
    except Exception as exc:
        app.logger.exception("Failed to create product")
        return jsonify({"error": "Database error", "details": str(exc)}), 500


if __name__ == "__main__":
    initialize_database(max_attempts=1)
    app.run(host="0.0.0.0", port=5000)
