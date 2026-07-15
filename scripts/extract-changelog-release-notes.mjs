#!/usr/bin/env node

import { readFileSync, writeFileSync } from 'node:fs';

const [, , rawTag, outputPath = 'release-notes.md'] = process.argv;

if (!rawTag) {
  console.error('Usage: node scripts/extract-changelog-release-notes.mjs <tag> [output-path]');
  process.exit(1);
}

const version = rawTag.replace(/^v/, '');
const changelog = readFileSync('CHANGELOG.md', 'utf8').replace(/\r\n/g, '\n');
const headingPattern = new RegExp(`^## \\[${escapeRegExp(version)}\\](?:\\s+-\\s+.*)?$`, 'm');
const match = headingPattern.exec(changelog);

if (!match) {
  console.error(`Could not find CHANGELOG.md section for ${rawTag} (${version}).`);
  process.exit(1);
}

const sectionStart = match.index;
const nextHeading = changelog.slice(sectionStart + match[0].length).search(/\n## \[/);
const sectionEnd =
  nextHeading === -1 ? changelog.length : sectionStart + match[0].length + nextHeading;
const notes = changelog.slice(sectionStart, sectionEnd).trim();

if (!notes) {
  console.error(`CHANGELOG.md section for ${rawTag} is empty.`);
  process.exit(1);
}

writeFileSync(outputPath, `${notes}\n`, 'utf8');
console.log(`Wrote release notes for ${rawTag} to ${outputPath}`);

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
