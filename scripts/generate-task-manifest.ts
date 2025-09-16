import * as fs from 'fs';
import * as path from 'path';
import * as yaml from 'js-yaml';

interface Task {
  id: string;
  title: string;
  difficulty: string;
  estimated_time: number;
  tags: string[];
  description: string;
}

interface TaskManifest {
  version: string;
  repository: string;
  total_tasks: number;
  categories: { [key: string]: string[] };
  difficulty_distribution: { [key: string]: number };
  estimated_total_time: number;
  tasks: Task[];
}

const tasksDir = path.join(__dirname, '../tasks');

function findTaskYamlFiles(dir: string): string[] {
  const files = fs.readdirSync(dir);
  let yamlFiles: string[] = [];

  for (const file of files) {
    const filePath = path.join(dir, file);
    const stat = fs.statSync(filePath);

    if (stat.isDirectory()) {
      yamlFiles = yamlFiles.concat(findTaskYamlFiles(filePath));
    } else if (file === 'task.yaml') {
      yamlFiles.push(filePath);
    }
  }

  return yamlFiles;
}

function generateTaskManifest() {
  const taskYamlFiles = findTaskYamlFiles(tasksDir);
  const tasks: Task[] = [];

  for (const filePath of taskYamlFiles) {
    const fileContent = fs.readFileSync(filePath, 'utf8');
    const taskData = yaml.load(fileContent) as any;
    tasks.push({
      id: taskData.id,
      title: taskData.title,
      difficulty: taskData.difficulty,
      estimated_time: taskData.estimated_time,
      tags: taskData.tags,
      description: taskData.description,
    });
  }

  const manifest: TaskManifest = {
    version: '1.0',
    repository: 'cli-arena-web-nextjs',
    total_tasks: tasks.length,
    categories: {},
    difficulty_distribution: {},
    estimated_total_time: tasks.reduce((acc, task) => acc + task.estimated_time, 0),
    tasks: tasks,
  };

  // Populate categories and difficulty_distribution
  for (const task of tasks) {
    const category = task.id.split('-')[1]; // e.g., 'cli-async-background-jobs' -> 'async'
    if (!manifest.categories[category]) {
      manifest.categories[category] = [];
    }
    manifest.categories[category].push(task.id);

    if (!manifest.difficulty_distribution[task.difficulty]) {
      manifest.difficulty_distribution[task.difficulty] = 0;
    }
    manifest.difficulty_distribution[task.difficulty]++;
  }

  fs.writeFileSync(path.join(__dirname, '../tasks.json'), JSON.stringify(manifest, null, 2));
  console.log('✅ Task manifest generated successfully!');
}

generateTaskManifest();
