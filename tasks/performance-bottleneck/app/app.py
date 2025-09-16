from flask import Flask, request, jsonify

app = Flask(__name__)

# Generate a large list of items to search through.
data = [f"item_{i}" for i in range(20000)]

def search_items(query, dataset):
    """
    This function searches for an exact match for a query in the data.
    It is intentionally inefficient.
    """
    results = []
    # BOTTLENECK: This is a slow way to find an exact match in a large list.
    for item in dataset:
        if item == query:
            results.append(item)
            break
    return results

@app.route('/search')
def search_route():
    query = request.args.get('q')
    if not query:
        return jsonify({"error": "Query parameter 'q' is required"}), 400

    results = search_items(query, data)
    return jsonify(results)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
