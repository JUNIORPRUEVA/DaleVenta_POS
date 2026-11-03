const {test} = require('node:test');
const assert = require('node:assert/strict');
const {assertTarget,assertPassword,assertVacant} = require('./create-synthetic-admin.cjs');
const env={APP_ENV:'uat',UAT_LOCAL_ONLY:'true',DATABASE_URL:'postgresql://127.0.0.1:56550/fullpos_alanube_uat'};
test('only the isolated UAT URL and disabled fiscal switches are allowed',()=>{
  assert.doesNotThrow(()=>assertTarget(env));
  for(const change of [{APP_ENV:'production'},{UAT_LOCAL_ONLY:'false'},{DATABASE_URL:'postgresql://remote:56550/fullpos_alanube_uat'},{DATABASE_URL:'postgresql://127.0.0.1:5432/fullpos_alanube_uat'},{DATABASE_URL:'postgresql://127.0.0.1:56550/production'},{DATABASE_URL:'https://127.0.0.1:56550/fullpos_alanube_uat'},{DATABASE_URL:'postgresql://127.0.0.1:56550/fullpos_alanube_uat?host=remote'},{ECF_EMISSION_ENABLED:'true'}]) assert.throws(()=>assertTarget({...env,...change}));
});
test('password cannot be silently truncated by bcrypt or passed through as invalid data',()=>{
  assert.doesNotThrow(()=>assertPassword('synthetic-test-only-value'));
  for(const value of [undefined,'short','x'.repeat(73),'x\n'.repeat(8),'é'.repeat(37)]) assert.throws(()=>assertPassword(value));
});
test('existing identities are never adopted or overwritten',()=>{
  assert.doesNotThrow(()=>assertVacant(null,null));
  assert.throws(()=>assertVacant({id:'synthetic'},null));assert.throws(()=>assertVacant(null,{id:'real'}));
});
