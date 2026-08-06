import { createRequire } from 'node:module';
const require = createRequire('/root/.claude/skills/oculus/node_modules/.package-lock.json');
const { firefox } = require('playwright');

const USER = process.env.SMOKE_USER || 'smoketest';
const PASS = process.env.SMOKE_PASS || 'smoketest123';
const PORT = process.env.PORT || '4000';
const URL = `http://localhost:${PORT}`;
const OUT = process.env.SCREENSHOT_PATH || '/tmp/terminal-ui.png';

const browser = await firefox.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });

try {
  await page.goto(URL);
  await page.waitForSelector('input[type="text"]', { timeout: 10000 });

  await page.fill('input[type="text"]', USER);
  await page.fill('input[type="password"]', PASS);
  await page.click('button[type="submit"]');

  // Wait for the login form to disappear and terminal content to appear.
  // The login form goes away on success; look for text unique to the terminal:
  // the quick-action buttons ("look", "inventory") or the command input placeholder.
  await page.waitForFunction(
    () => document.body.innerText.includes('look') && document.body.innerText.includes('inventory'),
    { timeout: 10000 }
  );
  await page.waitForTimeout(1500);

  await page.screenshot({ path: OUT, fullPage: true });
  console.log(`screenshot saved to ${OUT}`);

  const errors = await page.evaluate(() =>
    performance.getEntriesByType('resource')
      .filter(r => r.responseStatus >= 400)
      .map(r => `${r.responseStatus} ${r.name}`)
  );
  if (errors.length) {
    console.log('resource errors:', errors);
  }
} finally {
  await browser.close();
}
