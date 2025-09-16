import unittest
from app import search_items

class TestSearchAlgorithm(unittest.TestCase):

    def setUp(self):
        """Set up a sample dataset for testing."""
        self.test_data = ["apple", "banana", "cherry", "date"]

    def test_successful_search(self):
        """Test finding an item that exists in the dataset."""
        result = search_items("banana", self.test_data)
        self.assertEqual(result, ["banana"])

    def test_unsuccessful_search(self):
        """Test searching for an item that does not exist."""
        result = search_items("grape", self.test_data)
        self.assertEqual(result, [])

    def test_empty_query(self):
        """Test searching with an empty query string."""
        result = search_items("", self.test_data)
        self.assertEqual(result, [])

    def test_empty_dataset(self):
        """Test searching in an empty dataset."""
        result = search_items("apple", [])
        self.assertEqual(result, [])

if __name__ == '__main__':
    unittest.main()
