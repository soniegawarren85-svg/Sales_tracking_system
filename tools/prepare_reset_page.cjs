'use strict';

const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const source = path.join(root, 'web', 'account');
const destination = path.join(root, 'functions', 'reset_page');

for (const file of ['reset.html', 'reset.js']) {
  const sourceFile = path.join(source, file);
  if (!fs.existsSync(sourceFile)) {
    throw new Error(`Missing password reset page asset: ${sourceFile}`);
  }
}

fs.mkdirSync(destination, {recursive: true});
for (const file of ['reset.html', 'reset.js']) {
  fs.copyFileSync(path.join(source, file), path.join(destination, file));
}
