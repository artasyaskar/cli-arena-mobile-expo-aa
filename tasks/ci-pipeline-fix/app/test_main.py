import unittest
from main import add, subtract, multiply

class TestCalculator(unittest.TestCase):

    def test_add(self):
        """Test the add function."""
        self.assertEqual(add(2, 3), 5)
        self.assertEqual(add(-1, 1), 0)

    def test_subtract(self):
        """Test the subtract function. This test will fail."""
        self.assertEqual(subtract(5, 3), 2)

    def test_multiply(self):
        """Test the multiply function."""
        self.assertEqual(multiply(2, 3), 6)
        self.assertEqual(multiply(-1, 5), -5)

if __name__ == '__main__':
    unittest.main()
