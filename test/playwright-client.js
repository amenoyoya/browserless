/**
 * Browserless scraping test
 */
const {chromium} = require('playwright');

(async () => {
  // Playwright CDP Server 接続
  const browser = await chromium.connect({
    // endpoint: https-portal で公開している場合は環境変数 WEBSOCKET=true を指定しておく
    wsEndpoint: 'http://localhost:8099'
  });
  // ブラウザ操作
  const page = await browser.newPage();
  await page.goto('https://www.google.com', {waitUntil: 'networkidle'});
  await page.screenshot({
    path: `${__dirname}/google.com.png`,
    fullPage: true,
  });
  browser.close();
})();