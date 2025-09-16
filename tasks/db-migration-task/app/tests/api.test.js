const request = require('supertest');
const app = require('../index'); // Adjust the path to your Express app
const knex = require('knex')(require('../knexfile'));

// A helper function to run migrations and seed data
const setupTestDatabase = async () => {
  await knex.migrate.latest();
  await knex.seed.run();
};

// A helper function to rollback migrations
const teardownTestDatabase = async () => {
  await knex.migrate.rollback();
};

describe('User API', () => {
  beforeAll(async () => {
    // Note: In a real scenario, you'd run this against a separate test database.
    // For this task, we assume the user runs migrations on the dev DB.
  });

  afterAll(async () => {
    // Close the database connection
    await knex.destroy();
  });

  it('should return a user with a non-empty status field', async () => {
    // This test assumes a user with ID 1 exists.
    // The verify script will handle seeding the database.
    const response = await request(app).get('/users/1');

    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('id', 1);

    // This is the critical part of the test.
    // The `status` field should exist and not be the default 'status_not_available'.
    expect(response.body).toHaveProperty('status');
    expect(response.body.status).not.toBe('status_not_available');
    expect(response.body.status).toBe('active'); // Or whatever the migrated value is.
  });

  it('should have populated the status for all existing users', async () => {
    const users = await knex('users').select('*');
    // Ensure all users have a status that is not null.
    users.forEach(user => {
      expect(user.status).not.toBeNull();
      expect(user.status).toBe('active');
    });
  });
});
