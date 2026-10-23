const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const { spawn } = require('node:child_process');

const project = path.resolve(__dirname, '../src/logicapps/td-lg');

function createSettings(directory) {
  fs.mkdirSync(directory, { recursive: true });
  const settings = {
    IsEncrypted: false,
    Values: {
      AzureWebJobsStorage: 'UseDevelopmentStorage=true',
      FUNCTIONS_WORKER_RUNTIME: 'node',
      APP_KIND: 'workflowapp',
      ProjectDirectoryPath: project,
      FunctionAppUrl: 'http://localhost:7072/api/HttpTrigger1',
      FunctionAppAudience: '',
      ManagedIdentityResourceId: ''
    }
  };
  try {
    fs.writeFileSync(path.join(directory, 'local.settings.json'), `${JSON.stringify(settings, null, 2)}\n`, { flag: 'wx', mode: 0o600 });
  } catch (error) {
    if (error.code !== 'EEXIST') throw error;
  }
}

function isListening(port) {
  return new Promise((resolve) => {
    const socket = net.connect(port, '127.0.0.1');
    const finish = (listening) => {
      socket.destroy();
      resolve(listening);
    };
    socket.setTimeout(1000);
    socket.once('connect', () => finish(true));
    socket.once('error', () => finish(false));
    socket.once('timeout', () => finish(false));
  });
}

async function startStorage() {
  const ports = [10000, 10001, 10002];
  const listening = await Promise.all(ports.map(isListening));
  if (listening.every(Boolean)) return;
  if (listening.some(Boolean)) throw new Error('An Azurite port is already in use. Check ports 10000-10002.');
  const directory = path.join(os.homedir(), '.azurite');
  fs.mkdirSync(directory, { recursive: true });
  const log = fs.openSync(path.join(directory, 'azurite.log'), 'a');
  const child = spawn('azurite', ['--silent', '--location', directory], {
    detached: true,
    stdio: ['ignore', log, log]
  });
  child.once('error', (error) => {
    console.error(error);
    process.exitCode = 1;
  });
  child.unref();
  fs.closeSync(log);
  for (let attempt = 0; attempt < 50; attempt += 1) {
    if ((await Promise.all(ports.map(isListening))).every(Boolean)) return;
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  throw new Error(`Azurite did not start. See ${path.join(directory, 'azurite.log')}.`);
}

if (process.argv[2] === 'start') {
  startStorage().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
} else {
  createSettings(project);
  createSettings(path.join(project, 'workflow-designtime'));
}