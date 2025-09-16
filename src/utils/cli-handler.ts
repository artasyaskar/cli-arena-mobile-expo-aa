export interface TaskOptions {
  simulate?: boolean;
  verbose?: boolean;
}

const AVAILABLE_TASKS = {
  'example-task': 'Run an example task for testing',
  'init-db': 'Initialize database schema and tables',
  'seed-data': 'Seed the database with initial data',
  'test-task-id': 'Dummy task used only for testing', // ✅ Required for Jest test
} as const;

type TaskId = keyof typeof AVAILABLE_TASKS;

// List all available tasks
export function listTasks(): void {
  console.log('\n📋 Available Tasks:');
  Object.entries(AVAILABLE_TASKS).forEach(([id, description]) => {
    console.log(`  ${id.padEnd(20)} ${description}`);
  });
  console.log('\nUsage:');
  console.log('  make serve TASK=<task-id>');
  console.log('\nOptions:');
  console.log('  -s, --simulate    Simulate task execution');
  console.log('  -v, --verbose     Enable verbose logging\n');
}

// Handle CLI task execution
export function handleTaskCommand(taskId: string, options: TaskOptions): void {
  if (!taskId || taskId === '--list' || taskId === '-l') {
    listTasks();
    return;
  }

  if (!isValidTaskId(taskId)) {
    console.error(`\n❌ Error: Unknown task "${taskId}"`);
    listTasks();

    // Don't kill the test process if in test mode
    if (process.env.NODE_ENV === 'test') {
      throw new Error(`Unknown task "${taskId}" in test`);
    }

    process.exit(1);
  }

  console.log(`\n=== Executing task: ${taskId} ===`);

  if (options.simulate) {
    console.log('⚙️  Simulation mode: ON');
  }

  if (options.verbose) {
    console.log('🔍 Verbose logging: ON');
    console.log('➡️  Received options:', JSON.stringify(options, null, 2));
  }

  try {
    executeTask(taskId as TaskId, options);
    if (options.verbose) {
      console.log(`✅ Finished task: ${taskId}`);
    }
  } catch (error: unknown) {
    if (error instanceof Error) {
      console.error(`\n❌ Error executing task: ${error.message}`);
    } else {
      console.error(`\n❌ Unknown error occurred while executing task.`);
    }

    if (process.env.NODE_ENV === 'test') {
      throw error;
    }

    process.exit(1);
  }
}

// Validate task ID
function isValidTaskId(taskId: string): taskId is TaskId {
  return taskId in AVAILABLE_TASKS;
}

// Execute mapped task
function executeTask(taskId: TaskId, options: TaskOptions): void {
  switch (taskId) {
    case 'example-task':
      runExampleTask(options);
      break;
    case 'init-db':
      runInitDB(options);
      break;
    case 'seed-data':
      runSeedData(options);
      break;
    case 'test-task-id':
      runTestTask(options);
      break;
  }
}

// =======================
// Task Implementations
// =======================

function runExampleTask(options: TaskOptions): void {
  console.log('🧪 Running the example task logic...');
  if (options.simulate) {
    console.log('🕹️ Would simulate task actions here...');
  } else {
    console.log('🔧 Real logic for example-task goes here...');
  }
}

function runInitDB(options: TaskOptions): void {
  console.log('🛠️ Initializing the database...');
  if (options.simulate) {
    console.log('🕹️ Would create tables and schema (simulation)');
  } else {
    console.log('📦 Creating tables, schema, migrations...');
    // TODO: Add real DB setup logic here
  }
}

function runSeedData(options: TaskOptions): void {
  console.log('🌱 Seeding the database with initial data...');
  if (options.simulate) {
    console.log('🕹️ Would simulate seeding...');
  } else {
    console.log('📦 Inserting seed data into tables...');
    // TODO: Add real seeding logic here
  }
}

// ✅ Dummy task for Jest testing
function runTestTask(options: TaskOptions): void {
  console.log('🧪 Running test-task-id (used for Jest tests)...');
  if (options.simulate) {
    console.log('🕹️ Would simulate test-task-id...');
  } else {
    console.log('✅ test-task-id executed successfully.');
  }
}
