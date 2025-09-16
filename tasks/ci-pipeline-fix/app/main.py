import os # This import is unused, which will cause a linting error.

def add(a, b):
  """This function adds two numbers."""
  if not isinstance(a, (int, float)) or not isinstance(b, (int, float)):
    raise TypeError("Both inputs must be numbers")
  return a + b

def subtract(a, b):
  """This function is supposed to subtract two numbers, but it has a bug."""
  # BUG: This should be a - b
  # This very long comment is intentionally here to make sure that the line length check in the linter will fail.
  if not isinstance(a, (int, float)) or not isinstance(b, (int, float)):
    raise TypeError("Both inputs must be numbers")
  return a + b

def multiply(a, b):
  """This function multiplies two numbers."""
  if not isinstance(a, (int, float)) or not isinstance(b, (int, float)):
    raise TypeError("Both inputs must be numbers")
  return a * b
