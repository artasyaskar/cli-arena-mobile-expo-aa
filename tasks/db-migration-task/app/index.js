const express = require('express');
const knex = require('knex')(require('./knexfile'));

const app = express();
const port = 3000;

app.use(express.json());

// Endpoint to get all users
app.get('/users', async (req, res) => {
  try {
    const users = await knex('users').select('*');
    res.json(users);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch users', details: error.message });
  }
});

// Endpoint to get a specific user and their status
app.get('/users/:id', async (req, res) => {
  try {
    const user = await knex('users').where({ id: req.params.id }).first();
    if (user) {
      // This is the part that will work correctly only after the migration.
      // The 'status' column does not exist initially.
      const status = user.status || 'status_not_available';
      res.json({ ...user, status });
    } else {
      res.status(404).json({ error: 'User not found' });
    }
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch user', details: error.message });
  }
});

if (require.main === module) {
  app.listen(port, () => {
    console.log(`Server listening on port ${port}`);
  });
}

module.exports = app; // Export for testing purposes
