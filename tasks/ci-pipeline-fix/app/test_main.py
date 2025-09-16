import unittest
from main import add, subtract, multiply

class TestCalculator(unittest.TestCase):

    def test_add(self):
        """Test the add function with various inputs."""
        self.assertEqual(add(2, 3), 5)
        self.assertEqual(add(-1, 1), 0)
        self.assertEqual(add(-5, -5), -10)
        self.assertEqual(add(0, 0), 0)

    def test_subtract(self):
        """Test the subtract function. This test will fail initially."""
        self.assertEqual(subtract(5, 3), 2)
        self.assertEqual(subtract(10, 5), 5)
        self.assertEqual(subtract(-5, -5), 0)
        self.assertEqual(subtract(0, 5), -5)

    def test_multiply(self):
        """Test the multiply function."""
        self.assertEqual(multiply(2, 3), 6)
        self.assertEqual(multiply(-1, 5), -5)
        self.assertEqual(multiply(10, 0), 0)

    def test_error_handling(self):
        """Test that functions raise TypeError for non-numeric input."""
        with self.assertRaises(TypeError):
            add("a", 2)
        with self.assertRaises(TypeError):
            subtract(10, "b")
        with self.assertRaises(TypeError):
            multiply(None, 5)

if __name__ == '__main__':
    unittest.main()
