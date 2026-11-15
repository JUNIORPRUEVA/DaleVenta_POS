import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { appLinks, downloads } from '../src/config/site.ts';

test('Android has one active Google Play download matching the Flutter app', () => {
  const expected = 'https://play.google.com/store/apps/details?id=com.daleventa.pos';
  assert.equal(appLinks.android, expected);
  const android = downloads.filter(item => item.id === 'android');
  assert.equal(android.length, 1);
  assert.equal(android[0].url, expected);
  assert.equal(android[0].pending, undefined);
  assert.equal(android[0].status, 'Google Play');
  const flutterLinks = readFileSync(new URL('../../apps/fulltech_app/lib/core/app_access/app_access_links.dart', import.meta.url), 'utf8');
  assert.ok(flutterLinks.includes(expected));
  assert.ok(!flutterLinks.includes('app-release.apk'));
});
