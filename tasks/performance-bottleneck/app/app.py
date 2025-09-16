from flask import Flask, request, jsonify

app = Flask(__name__)

# Generate a large list of items to search through.
data = [f"item_{i}" for i in range(20000)]

@app.route('/search')
def search():
    """
    This endpoint searches for an exact match for a query in the data.
    It is intentionally inefficient.
    """
    query = request.args.get('q')
    if not query:
        return jsonify({"error": "Query parameter 'q' is required"}), 400

    results = []
    # BOTTLENECK: This is a slow way to find an exact match in a large list.
    # The complexity is O(n). A developer should identify this as the problem.
    # A better solution would be to use a data structure with O(1) lookup time.
    for item in data:
        if item == query:
            results.append(item)
            break  # Found it, no need to continue

    return jsonify(results)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
