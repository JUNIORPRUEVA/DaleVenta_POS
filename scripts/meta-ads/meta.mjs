#!/usr/bin/env node
/**
 * FullPOS Cloud — Meta Ads campaign migration (API only, no browser automation).
 *
 *   node scripts/meta-ads/meta.mjs <command> [--account act_XXXX] [--campaign ID]
 *
 * Commands are staged and safe to re-run. Nothing is written to Meta by
 * preflight / discover / audit / plan / verify / compare / status.
 *
 *   preflight  -> token validity, scopes, reachable objects            out/01-preflight.json
 *   discover   -> business, ad account(s), page, IG, pixel/dataset      out/02-discovery.json
 *   audit      -> locate the ACTIVE FullPOS campaign + full baseline    out/BASELINE_FULLPOS_ADS.json
 *   plan       -> build the OLD vs NEW payloads (no writes)             out/03-plan.json
 *   create     -> idempotent creation of the new paused hierarchy       out/04-created.json
 *   verify     -> independent GET of the new hierarchy                  out/05-verify.json
 *   compare    -> OLD vs NEW comparison table                           out/06-comparison.json
 *   landing    -> landing page reachability + required copy             out/07-landing.json
 *   cutover    -> activate replacement, then pause the old campaign     out/08-cutover.json
 *   rollback   -> restore the original campaign as ACTIVE               out/09-rollback.json
 *   status     -> read-only status of old and new hierarchies
 */

import {
  DEFAULT_ENV_FILE,
  Logger,
  MetaClient,
  GraphError,
  envPresence,
  loadSecrets,
  makeRedactor,
  readJson,
  resolveApiVersion,
} from './lib/graph.mjs';

/* ------------------------------------------------------------------ */
/* constants                                                           */
/* ------------------------------------------------------------------ */

const OLD_CAMPAIGN_NAME_HINT = 'FullPOS01';const NEW_CAMPAIGN_NAME_BASE = 'FullPOS02 - Registro Web';
const LANDING_URL = 'https://fullposcloud.fulltechrd.com/';
const LANDING_REQUIRED_STRINGS = ['Regístrate gratis ahora', 'Prueba FullPOS gratis por 7 días'];
/** Control strings: if these are not found either, the search itself is broken and
 *  a negative result for the required copy would be meaningless. */
const LANDING_CONTROL_STRINGS = ['FullPOS', 'gratis', 'registr'];
/** Routes that must serve the app in production (checked plain and hash form,
 *  because a Flutter web app may be served either way). */
const LANDING_ROUTES = ['/register', '/login'];
const TARGET_EVENT = 'RegistrationStarted';

/** Read-only targeting representations: Meta returns them but refuses them on
 *  write. They carry no audience semantics (age_min/age_max hold the real
 *  values), so they are stripped before POST and excluded from the equality
 *  check — always reported explicitly, never silently ignored. */
const READONLY_TARGETING_KEYS = ['age_range', 'user_age_unknown'];

const CAMPAIGN_FIELDS = [
  'id', 'name', 'objective', 'status', 'effective_status', 'configured_status',
  'buying_type', 'special_ad_categories', 'special_ad_category_country',
  'daily_budget', 'lifetime_budget', 'budget_remaining',
  'is_adset_budget_sharing_enabled',
  'created_time', 'updated_time', 'start_time', 'stop_time',
  'account_id', 'smart_promotion_type', 'source_campaign_id', 'is_skadnetwork_attribution',
].join(',');

const ADSET_FIELDS = [
  'id', 'name', 'campaign_id', 'status', 'effective_status', 'configured_status',
  'daily_budget', 'lifetime_budget', 'budget_remaining', 'daily_spend_cap', 'daily_min_spend',
  'billing_event', 'optimization_goal', 'optimization_sub_event', 'bid_strategy', 'bid_amount',
  'bid_constraints', 'pacing_type', 'destination_type', 'promoted_object', 'attribution_spec',
  'start_time', 'end_time', 'targeting', 'is_dynamic_creative', 'use_new_app_click',
  'frequency_control_specs', 'multiadvertiser_audience_setting', 'created_time', 'updated_time',
].join(',');

const CREATIVE_FIELDS_FULL = [
  'id', 'name', 'status', 'object_type', 'account_id',
  'title', 'body', 'link_url', 'call_to_action_type', 'url_tags',
  'image_hash', 'image_url', 'video_id', 'thumbnail_url',
  'object_story_id', 'effective_object_story_id', 'object_story_spec',
  'instagram_actor_id', 'instagram_permalink_url', 'asset_feed_spec', 'degrees_of_freedom_spec',
].join(',');

const CREATIVE_FIELDS_REDUCED = [
  'id', 'name', 'status', 'object_type', 'account_id',
  'title', 'body', 'link_url', 'call_to_action_type', 'url_tags',
  'image_hash', 'video_id', 'thumbnail_url',
  'object_story_id', 'effective_object_story_id', 'object_story_spec', 'instagram_actor_id',
].join(',');

const CREATIVE_FIELDS_MIN = [
  'id', 'name', 'video_id', 'image_hash', 'link_url', 'body', 'title',
  'call_to_action_type', 'url_tags', 'object_story_id', 'object_story_spec', 'instagram_actor_id', 'thumbnail_url',
].join(',');

const AD_BASE_FIELDS = [
  'id', 'name', 'campaign_id', 'adset_id', 'status', 'effective_status', 'configured_status',
  'created_time', 'updated_time', 'tracking_specs', 'issues_info',
  'adset{id,name,optimization_goal,destination_type,promoted_object}',
].join(',');

/** Tried in order; the first one Meta accepts becomes the one used for the run. */
const AD_FIELDS_CANDIDATES = [
  `${AD_BASE_FIELDS},creative{${CREATIVE_FIELDS_FULL}}`,
  `${AD_BASE_FIELDS},creative{${CREATIVE_FIELDS_REDUCED}}`,
  `${AD_BASE_FIELDS},creative{${CREATIVE_FIELDS_MIN}}`,
  'id,name,campaign_id,adset_id,status,effective_status,configured_status,creative{id,name,video_id,object_story_id,object_story_spec,link_url}',
];

let adsFieldsInUse = null;
const INSIGHT_FIELDS = [
  'spend', 'impressions', 'reach', 'frequency', 'clicks', 'unique_clicks',
  'inline_link_clicks', 'inline_link_click_ctr', 'outbound_clicks', 'outbound_clicks_ctr',
  'ctr', 'cpc', 'cpm', 'cpp', 'actions', 'cost_per_action_type', 'date_start', 'date_stop',
].join(',');

const INSIGHT_FIELDS_EXTENDED = `${INSIGHT_FIELDS},results,cost_per_result,optimization_goal,attribution_setting`;

const CAMPAIGN_FIELDS_CANDIDATES = [
  CAMPAIGN_FIELDS,
  'id,name,objective,status,effective_status,buying_type,special_ad_categories,daily_budget,lifetime_budget,created_time,updated_time,start_time,stop_time,account_id',
  'id,name,objective,status,effective_status,daily_budget,lifetime_budget,special_ad_categories,buying_type',
];

const ADSET_FIELDS_CANDIDATES = [
  ADSET_FIELDS,
  [
    'id', 'name', 'campaign_id', 'status', 'effective_status', 'daily_budget', 'lifetime_budget',
    'billing_event', 'optimization_goal', 'bid_strategy', 'bid_amount', 'destination_type',
    'promoted_object', 'attribution_spec', 'start_time', 'end_time', 'targeting', 'pacing_type',
  ].join(','),
  [
    'id', 'name', 'campaign_id', 'status', 'effective_status', 'daily_budget', 'lifetime_budget',
    'billing_event', 'optimization_goal', 'bid_strategy', 'destination_type', 'promoted_object', 'targeting',
  ].join(','),
];

/** Fields Meta returns on read but may reject on write. Only these may be dropped,
 *  and only when Meta itself names them. Anything else -> STOP. */
const STRIPPABLE_TARGETING_FIELDS = [  'targeting_optimization',
  'targeting_relaxation',
  'ap_filter_flags',
  'publisher_platforms_automation',
  'existing_customer_budget_percentage',
  'excluded_publisher_categories',
  'excluded_publisher_domains',
  'excluded_publisher_list_ids',
];

/* ------------------------------------------------------------------ */
/* helpers                                                             */
/* ------------------------------------------------------------------ */

const iso = () => new Date().toISOString();

class StopError extends Error {
  constructor(reason, details) {
    super(reason);
    this.name = 'StopError';
    this.reason = reason;
    this.details = details;
  }
}

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith('--')) args[key] = true;
      else {
        args[key] = next;
        i += 1;
      }
    } else args._.push(a);
  }
  return args;
}

/**
 * Landing URL of a creative. Meta stores it in different places depending on the
 * ad format (link_data / video_data / photo_data / asset_feed_spec), and video ads
 * — which is the FullPOS case — keep it under video_data.call_to_action.value.
 */
function creativeLandingUrl(creative) {
  if (!creative) return null;
  const spec = creative.object_story_spec ?? {};
  const candidates = [
    creative.link_url,
    spec.link_data?.link,
    spec.link_data?.call_to_action?.value?.link,
    spec.video_data?.call_to_action?.value?.link,
    spec.photo_data?.call_to_action?.value?.link,
    spec.template_data?.call_to_action?.value?.link,
    creative.asset_feed_spec?.link_urls?.[0]?.website_url,
  ];
  return candidates.find((v) => typeof v === 'string' && v.length > 0) ?? null;
}

function creativePageId(creative) {
  if (!creative) return null;
  return creative.object_story_spec?.page_id ?? creative.effective_object_story_id?.split('_')?.[0] ?? null;
}

function creativeInstagramUserId(creative) {
  if (!creative) return null;
  return creative.object_story_spec?.instagram_user_id ?? creative.instagram_actor_id ?? null;
}

/** Creative-level video id and story-level video id can differ; both are compared. */
function creativeVideoIds(creative) {
  if (!creative) return { creative_video_id: null, story_video_id: null };
  return {
    creative_video_id: creative.video_id ?? null,
    story_video_id: creative.object_story_spec?.video_data?.video_id ?? null,
  };
}

function creativeBody(creative) {
  return creative?.body ?? creative?.object_story_spec?.video_data?.message ?? creative?.object_story_spec?.link_data?.message ?? null;
}

function creativeHeadline(creative) {
  return creative?.title ?? creative?.object_story_spec?.video_data?.title ?? creative?.object_story_spec?.link_data?.name ?? null;
}

function creativeCallToAction(creative) {
  return creative?.call_to_action_type ?? creative?.object_story_spec?.video_data?.call_to_action?.type ?? null;
}

async function tryGet(client, logger, label, endpoint, params = {}) {
  try {
    const data = await client.get(endpoint, params);
    return { ok: true, data };
  } catch (err) {
    const detail = err instanceof GraphError ? err.toJSON() : { message: String(err.message) };
    logger.warn(`read failed: ${label}`, { endpoint, error: detail });
    return { ok: false, error: detail, endpoint };
  }
}

/**
 * Meta rejects the WHOLE request when one field is unknown, so every read tries
 * progressively narrower field sets. The set that worked is cached for the run,
 * which keeps the audit from aborting on a single unsupported field name.
 */
async function resolveAccessor({ client, logger, label, candidates, cache, run }) {
  const ordered = cache.value ? [cache.value, ...candidates.filter((c) => c !== cache.value)] : [...candidates];
  let lastError = null;
  for (const candidate of ordered) {
    try {
      const data = await run(candidate);
      if (cache.value !== candidate) logger.info(`${label}: field set accepted`, { fields: candidate });
      cache.value = candidate;
      return data;
    } catch (err) {
      lastError = err;
      const detail = err instanceof GraphError ? err.toJSON() : { message: String(err.message) };
      // Only a field complaint means "try a narrower field set". Anything else
      // (rate limit, permissions, transient) must not be amplified by retrying.
      if (err instanceof GraphError && !err.isFieldError) throw err;
      logger.warn(`${label}: field set rejected, narrowing`, { error: detail.message, code: detail.code });
    }
  }
  throw lastError;
}

const adsFieldCache = { value: null };
const adsetFieldCache = { value: null };
const campaignFieldCache = { value: null };

/** Set during bootstrap so helpers can log without threading the logger through
 *  every call site. Diagnostics only — never a secret. */
let activeLogger = { info() {}, warn() {}, error() {}, step() {} };

const fetchAdsForCampaign = (client, logger, campaignId, extra = {}) =>
  resolveAccessor({ client, logger, label: `ads ${campaignId}`, candidates: AD_FIELDS_CANDIDATES, cache: adsFieldCache, run: (fields) => client.all(`${campaignId}/ads`, { fields, ...extra }) });

const fetchAd = (client, logger, adId) =>
  resolveAccessor({ client, logger, label: `ad ${adId}`, candidates: AD_FIELDS_CANDIDATES, cache: adsFieldCache, run: (fields) => client.get(adId, { fields }) });

const fetchAdsetsForCampaign = (client, logger, campaignId, extra = {}) =>
  resolveAccessor({ client, logger, label: `adsets ${campaignId}`, candidates: ADSET_FIELDS_CANDIDATES, cache: adsetFieldCache, run: (fields) => client.all(`${campaignId}/adsets`, { fields, ...extra }) });

const fetchAdset = (client, logger, adsetId) =>
  resolveAccessor({ client, logger, label: `adset ${adsetId}`, candidates: ADSET_FIELDS_CANDIDATES, cache: adsetFieldCache, run: (fields) => client.get(adsetId, { fields }) });

const fetchCampaign = (client, logger, campaignId) =>
  resolveAccessor({ client, logger, label: `campaign ${campaignId}`, candidates: CAMPAIGN_FIELDS_CANDIDATES, cache: campaignFieldCache, run: (fields) => client.get(campaignId, { fields }) });

const fetchCampaignsForAccount = (client, logger, accountId, extra = {}) =>
  resolveAccessor({ client, logger, label: `campaigns ${accountId}`, candidates: CAMPAIGN_FIELDS_CANDIDATES, cache: campaignFieldCache, run: (fields) => client.all(`${accountId}/campaigns`, { fields, ...extra }) });

function summarizeInsights(row) {
  if (!row) return null;
  const actions = Object.fromEntries((row.actions ?? []).map((a) => [a.action_type, Number(a.value)]));
  const costPerAction = Object.fromEntries(
    (row.cost_per_action_type ?? []).map((a) => [a.action_type, Number(a.value)]),
  );
  const lpv = actions.landing_page_view ?? null;
  const spend = row.spend != null ? Number(row.spend) : null;
  return {
    date_start: row.date_start,
    date_stop: row.date_stop,
    spend,
    impressions: row.impressions != null ? Number(row.impressions) : null,
    reach: row.reach != null ? Number(row.reach) : null,
    frequency: row.frequency != null ? Number(row.frequency) : null,
    clicks: row.clicks != null ? Number(row.clicks) : null,
    unique_clicks: row.unique_clicks != null ? Number(row.unique_clicks) : null,
    link_clicks: row.inline_link_clicks != null ? Number(row.inline_link_clicks) : null,
    outbound_clicks: row.outbound_clicks?.[0]?.value != null ? Number(row.outbound_clicks[0].value) : null,
    landing_page_views: lpv,
    cost_per_landing_page_view: costPerAction.landing_page_view ?? (spend != null && lpv ? Number((spend / lpv).toFixed(4)) : null),
    ctr: row.ctr != null ? Number(row.ctr) : null,
    link_ctr: row.inline_link_click_ctr != null ? Number(row.inline_link_click_ctr) : null,
    cpc: row.cpc != null ? Number(row.cpc) : null,
    cpm: row.cpm != null ? Number(row.cpm) : null,
    results: row.results != null ? row.results : null,
    cost_per_result: row.cost_per_result != null ? row.cost_per_result : null,
    actions,
    cost_per_action_type: costPerAction,
  };
}

async function fetchInsights(client, logger, objectId, level = 'campaign', { extended = false } = {}) {
  const primary = await tryGet(client, logger, `insights ${level} ${objectId}`, `${objectId}/insights`, {
    fields: INSIGHT_FIELDS,
    date_preset: 'maximum',
    level,
  });
  let extra = null;
  if (primary.ok && extended) {
    extra = await tryGet(client, logger, `insights(extended) ${level} ${objectId}`, `${objectId}/insights`, {
      fields: INSIGHT_FIELDS_EXTENDED,
      date_preset: 'maximum',
      level,
    });
  }
  const row = (extra?.ok ? extra.data : primary.data)?.data?.[0] ?? null;
  return {
    raw: primary.ok ? primary.data?.data ?? [] : null,
    extended_raw: extra?.ok ? extra.data?.data ?? [] : null,
    error: primary.ok ? null : primary.error,
    summary: summarizeInsights(row),
  };
}

/* ------------------------------------------------------------------ */
/* context                                                             */
/* ------------------------------------------------------------------ */

async function bootstrap({ requireAdsManagement = false, commandName }) {
  const secrets = loadSecrets();
  const presence = envPresence(secrets);
  const missing = Object.entries(presence)
    .filter(([, v]) => v === 'MISSING')
    .map(([k]) => k);
  if (missing.length) throw new Error(`Missing required credential(s): ${missing.join(', ')}`);

  const redact = makeRedactor(secrets);
  const logger = new Logger(redact, commandName ?? 'meta');
  activeLogger = logger;
  logger.info('credential presence', presence);

  const versionInfo = await resolveApiVersion({
    token: secrets.META_ACCESS_TOKEN,
    appId: secrets.META_APP_ID,
    appSecret: secrets.META_APP_SECRET,
    redact,
  });
  logger.info('graph api version resolution', {
    started_with: versionInfo.attempts[0]?.version,
    resolved: versionInfo.version,
    mode: versionInfo.mode,
    probes: versionInfo.attempts.length,
    rejected: versionInfo.attempts.filter((a) => !a.ok).map((a) => ({ v: a.version, code: a.code, retired: a.retired })),
  });
  if (!versionInfo.version) throw new Error('No usable Graph API version could be resolved');

  const client = new MetaClient({
    version: versionInfo.version,
    token: secrets.META_ACCESS_TOKEN,
    appId: secrets.META_APP_ID,
    appSecret: secrets.META_APP_SECRET,
    logger,
    redact,
  });

  if (requireAdsManagement) {
    const dbg = await client.debugToken();
    const scopes = dbg.scopes ?? [];
    if (!scopes.includes('ads_management')) {
      throw new StopError('ADS_MANAGEMENT_MISSING', { scopes, token_type: dbg.type });
    }
  }

  return { secrets, presence, redact, logger, client, versionInfo };
}

/* ------------------------------------------------------------------ */
/* command: preflight (PHASE 1)                                        */
/* ------------------------------------------------------------------ */

async function cmdPreflight(ctx) {
  const { client, logger, versionInfo } = ctx;
  const dbg = await client.debugToken();
  const scopes = dbg.scopes ?? [];

  const me = await tryGet(client, logger, 'me', 'me', { fields: 'id,name' });
  const permissions = await tryGet(client, logger, 'me/permissions', 'me/permissions');
  const businesses = await tryGet(client, logger, 'me/businesses', 'me/businesses', {
    fields: 'id,name,verification_status,created_time',
  });
  const adAccounts = await tryGet(client, logger, 'me/adaccounts', 'me/adaccounts', {
    fields:
      'id,account_id,name,account_status,currency,time_zone,timezone_name,disable_reason,business,owner,is_prepay_account,amount_spent,balance,business_country_code,created_time',
  });

  const adsRead = scopes.includes('ads_read') && adAccounts.ok;
  const adsManagement = scopes.includes('ads_management');
  const businessManagement = scopes.includes('business_management') && businesses.ok;

  const artifact = {
    generated_at: iso(),
    graph_api: { version: client.version, mode: versionInfo.mode, probes: versionInfo.attempts },
    token: {
      is_valid: dbg.is_valid,
      type: dbg.type,
      app_id: dbg.app_id,
      application: dbg.application,
      user_id: dbg.user_id,
      issued_at: dbg.issued_at ? new Date(dbg.issued_at * 1000).toISOString() : null,
      expires_at: dbg.expires_at ? new Date(dbg.expires_at * 1000).toISOString() : null,
      data_access_expires_at: dbg.data_access_expires_at ? new Date(dbg.data_access_expires_at * 1000).toISOString() : null,
      scopes,
      granular_scopes: (dbg.granular_scopes ?? []).map((g) => ({ scope: g.scope, target_ids: g.target_ids ?? [] })),
      error: dbg.error ?? null,
    },
    identity: me.ok ? me.data : null,
    permissions: permissions.ok ? permissions.data?.data ?? null : null,
    checks: {
      ADS_READ: adsRead ? 'YES' : 'NO',
      ADS_MANAGEMENT: adsManagement ? 'YES' : 'NO',
      BUSINESS_MANAGEMENT: businessManagement ? 'YES' : 'NO',
    },
    businesses_seen: businesses.ok ? businesses.data?.data ?? [] : null,
    ad_accounts_seen: adAccounts.ok ? adAccounts.data?.data ?? [] : null,
  };

  logger.writeJson('01-preflight.json', artifact);
  logger.step('preflight summary', { ...artifact.checks, token_valid: dbg.is_valid, token_type: dbg.type });

  if (!dbg.is_valid) throw new StopError('TOKEN_INVALID', { token: artifact.token });
  if (!adsManagement) throw new StopError('ADS_MANAGEMENT_MISSING', { scopes });
  return artifact;
}

/* ------------------------------------------------------------------ */
/* command: discover (PHASE 2)                                         */
/* ------------------------------------------------------------------ */

async function cmdDiscover(ctx) {
  const { client, logger } = ctx;
  const pre = readJson('01-preflight.json');

  /* System-user tokens usually answer an empty `/me/businesses`, so the business
   * is resolved from the ad account's `business`/`owner` fields as well. */
  const businessIds = new Set();
  for (const b of pre?.businesses_seen ?? []) businessIds.add(b.id);
  for (const a of pre?.ad_accounts_seen ?? []) {
    if (a.business?.id) businessIds.add(a.business.id);
    if (a.owner) businessIds.add(String(a.owner));
  }

  const businessDetails = [];
  for (const businessId of businessIds) {
    const detail = await tryGet(client, logger, `business ${businessId}`, businessId, {
      fields: 'id,name,verification_status,created_time,primary_page,link',
    });
    const b = detail.ok ? { id: detail.data.id, name: detail.data.name, verification_status: detail.data.verification_status } : { id: businessId, name: null };
    const owned = await tryGet(client, logger, `owned_ad_accounts ${businessId}`, `${businessId}/owned_ad_accounts`, {
      fields: 'id,account_id,name,account_status,currency,timezone_name,business,disable_reason',
    });
    const client_ = await tryGet(client, logger, `client_ad_accounts ${businessId}`, `${businessId}/client_ad_accounts`, {
      fields: 'id,account_id,name,account_status,currency,timezone_name,business,disable_reason',
    });
    const ownedPages = await tryGet(client, logger, `owned_pages ${businessId}`, `${businessId}/owned_pages`, {
      fields: 'id,name,link,category,instagram_business_account{id,username}',
    });
    const clientPages = await tryGet(client, logger, `client_pages ${businessId}`, `${businessId}/client_pages`, {
      fields: 'id,name,link,category,instagram_business_account{id,username}',
    });
    const ownedPixels = await tryGet(client, logger, `owned_pixels ${businessId}`, `${businessId}/owned_pixels`, {
      fields: 'id,name,creation_time,last_fired_time,is_unavailable,owner_business,data_use_setting',
    });
    const adspixels = await tryGet(client, logger, `adspixels ${businessId}`, `${businessId}/adspixels`, {
      fields: 'id,name,creation_time,last_fired_time,is_unavailable,owner_business,data_use_setting',
    });
    businessDetails.push({
      id: businessId,
      name: b.name,
      verification_status: b.verification_status ?? null,
      detail_raw: detail.ok ? detail.data : null,
      detail_error: detail.ok ? null : detail.error,
      owned_ad_accounts: owned.ok ? owned.data?.data ?? [] : null,
      client_ad_accounts: client_.ok ? client_.data?.data ?? [] : null,
      owned_pages: ownedPages.ok ? ownedPages.data?.data ?? [] : null,
      client_pages: clientPages.ok ? clientPages.data?.data ?? [] : null,
      owned_pixels: ownedPixels.ok ? ownedPixels.data?.data ?? null : null,
      business_adspixels: adspixels.ok ? adspixels.data?.data ?? null : null,
    });
  }

  // Pages visible to the token (needed to reuse the same page/IG identity).
  const mePages = await tryGet(client, logger, 'me/accounts', 'me/accounts', {
    fields: 'id,name,link,category,instagram_business_account{id,username},tasks',
  });

  const adAccountsMap = new Map();
  for (const a of pre?.ad_accounts_seen ?? []) adAccountsMap.set(a.id, { ...a, source: 'me/adaccounts' });
  for (const b of businessDetails) {
    for (const a of b.owned_ad_accounts ?? []) adAccountsMap.set(a.id, { ...a, source: `business:${b.id}:owned`, business_id: b.id });
    for (const a of b.client_ad_accounts ?? []) adAccountsMap.set(a.id, { ...a, source: `business:${b.id}:client`, business_id: b.id });
  }

  const pixelsByAccount = {};
  for (const accountId of adAccountsMap.keys()) {
    const res = await tryGet(client, logger, `adspixels ${accountId}`, `${accountId}/adspixels`, {
      fields: 'id,name,creation_time,last_fired_time,is_unavailable,owner_business,data_use_setting,is_unified_pixel',
    });
    pixelsByAccount[accountId] = res.ok ? res.data?.data ?? [] : null;
  }

  const artifact = {
    generated_at: iso(),
    graph_api_version: client.version,
    businesses: businessDetails,
    pages_seen_by_token: mePages.ok ? mePages.data?.data ?? [] : null,
    ad_accounts: [...adAccountsMap.values()],
    pixels_by_ad_account: pixelsByAccount,
  };
  logger.writeJson('02-discovery.json', artifact);
  logger.step('discovery summary', {
    businesses: businessDetails.map((b) => ({ id: b.id, name: b.name })),
    ad_accounts: [...adAccountsMap.values()].map((a) => ({
      id: a.id,
      name: a.name,
      status: a.account_status,
      currency: a.currency,
      timezone: a.time_zone,
      source: a.source,
    })),
    pages: (mePages.data?.data ?? []).map((p) => ({ id: p.id, name: p.name, ig: p.instagram_business_account?.username ?? null })),
  });
  return artifact;
}

/* ------------------------------------------------------------------ */
/* command: campaigns (cheap listing, no deep reads)                   */
/* ------------------------------------------------------------------ */

async function cmdCampaigns(ctx, args) {
  const { client, logger } = ctx;
  const discovery = readJson('02-discovery.json');
  if (!discovery) throw new Error('Run `discover` first (missing out/02-discovery.json)');
  const accounts = (discovery.ad_accounts ?? []).filter((a) => {
    if (!args.account) return true;
    return a.id === args.account || a.account_id === String(args.account).replace(/^act_/, '');
  });

  const out = { generated_at: iso(), graph_api_version: client.version, accounts: [] };
  for (const account of accounts) {
    try {
      const campaigns = await fetchCampaignsForAccount(client, logger, account.id);
      out.accounts.push({
        account: { id: account.id, name: account.name, currency: account.currency, status: account.account_status },
        campaigns: campaigns.map((c) => ({
          id: c.id,
          name: c.name,
          objective: c.objective,
          status: c.status,
          effective_status: c.effective_status,
          created_time: c.created_time,
          updated_time: c.updated_time,
          daily_budget: c.daily_budget,
          lifetime_budget: c.lifetime_budget,
        })),
      });
    } catch (err) {
      const detail = err instanceof GraphError ? err.toJSON() : { message: String(err.message) };
      logger.warn('campaign listing failed', { account: account.id, error: detail });
      out.accounts.push({ account: { id: account.id, name: account.name }, error: detail });
    }
  }
  logger.writeJson('02b-campaigns.json', out);
  for (const a of out.accounts) {
    logger.step(`campaigns in ${a.account.id} (${a.account.name})`, {
      total: a.campaigns?.length ?? 0,
      active: (a.campaigns ?? []).filter((c) => c.effective_status === 'ACTIVE').length,
      fullpos_named: (a.campaigns ?? []).filter((c) => /fullpos/i.test(c.name ?? '')).map((c) => ({
        id: c.id, name: c.name, objective: c.objective, status: c.status, effective_status: c.effective_status,
      })),
    });
  }
  return out;
}

/* ------------------------------------------------------------------ */
/* command: audit (PHASES 3, 4, 5, 6)                                  */
/* ------------------------------------------------------------------ */

function isFullposCandidate(campaign, ads) {
  const nameMatch = /fullpos/i.test(campaign.name ?? '');
  const adLinks = ads.map((ad) => creativeLandingUrl(ad.creative)).filter(Boolean);
  const urlMatch = adLinks.some((l) => /fullposcloud\.fulltechrd\.com/i.test(l));
  return { nameMatch, urlMatch, adLinks };
}

async function loadHierarchy(client, logger, campaign) {
  const adsets = await fetchAdsetsForCampaign(client, logger, campaign.id);
  const ads = await fetchAdsForCampaign(client, logger, campaign.id);
  return { campaign, adsets, ads };
}

async function cmdAudit(ctx, args) {
  const { client, logger } = ctx;
  const discovery = readJson('02-discovery.json');
  if (!discovery) throw new Error('Run `discover` first (missing out/02-discovery.json)');

  const accounts = (discovery.ad_accounts ?? []).filter((a) => {
    if (!args.account) return true;
    return a.id === args.account || a.account_id === String(args.account).replace(/^act_/, '');
  });
  if (!accounts.length) throw new StopError('AD_ACCOUNT_NOT_FOUND', { requested: args.account ?? null });

  const activeFullpos = [];
  const allActive = [];
  const accountReports = [];

  for (const account of accounts) {
    /* (a) FullPOS-named campaigns, all statuses — one filtered call. */
    let named = [];
    let filterUsed = null;
    let namedError = null;
    for (const term of ['FullPOS', 'fullpos', 'POS']) {
      const res = await tryGet(client, logger, `campaigns(name~${term}) ${account.id}`, `${account.id}/campaigns`, {
        fields: CAMPAIGN_FIELDS,
        filtering: [{ field: 'name', operator: 'CONTAIN', value: term }],
      });
      if (res.ok) {
        named = res.data?.data ?? [];
        filterUsed = term;
        if (named.length) break;
      } else {
        namedError = res.error;
      }
    }

    /* (b) Every ACTIVE campaign, light fields only — needed to prove that no other
     *     FullPOS-related campaign is running under a completely different name.
     *     The shared account holds hundreds of active campaigns, so nothing here
     *     may do per-campaign deep reads (that is what triggered error 17). */
    const activeRes = await tryGet(client, logger, `campaigns(ACTIVE) ${account.id}`, `${account.id}/campaigns`, {
      fields: 'id,name,objective,status,effective_status,daily_budget,lifetime_budget,created_time,updated_time',
      filtering: [{ field: 'effective_status', operator: 'IN', value: ['ACTIVE'] }],
    });
    const activeList = activeRes.ok ? activeRes.data?.data ?? [] : [];
    allActive.push(...activeList.map((c) => ({ account_id: account.id, account_name: account.name, ...c })));

    const activeNamed = named.filter((c) => c.effective_status === 'ACTIVE' || c.status === 'ACTIVE');
    const activeWithFullposName = activeList.filter((c) => /fullpos/i.test(c.name ?? ''));

    for (const c of [...activeNamed, ...activeWithFullposName]) {
      if (activeFullpos.some((f) => f.campaign.id === c.id)) continue;
      activeFullpos.push({
        account,
        campaign: c,
        evidence: { nameMatch: true, urlMatch: null, adLinks: [], confirmed_by: 'name' },
        ads_present: null,
        plausible: true,
      });
    }

    accountReports.push({
      account: { id: account.id, name: account.name, currency: account.currency, status: account.account_status },
      name_filter_used: filterUsed,
      name_filter_error: namedError,
      campaigns_matching_name_filter: named.map((c) => ({
        id: c.id, name: c.name, objective: c.objective, status: c.status,
        effective_status: c.effective_status, daily_budget: c.daily_budget, lifetime_budget: c.lifetime_budget,
      })),
      active_campaigns_total: activeList.length,
      active_scan_error: activeRes.ok ? null : activeRes.error,
      active_campaigns_with_fullpos_in_name: activeWithFullposName.map((c) => ({
        id: c.id, name: c.name, objective: c.objective, effective_status: c.effective_status,
      })),
      other_active_campaign_names_sample: activeList
        .filter((c) => !/fullpos/i.test(c.name ?? ''))
        .slice(0, 25)
        .map((c) => ({ id: c.id, name: c.name, objective: c.objective })),
    });
  }

  if (!activeFullpos.length) {
    throw new StopError('NO_ACTIVE_FULLPOS_CAMPAIGN', {
      active_campaigns_seen: allActive.map((c) => ({ id: c.id, name: c.name, objective: c.objective, effective_status: c.effective_status })),
    });
  }

  const plausible = activeFullpos.filter((f) => f.plausible);
  if (!plausible.length) {
    throw new StopError('NO_ACTIVE_FULLPOS_CAMPAIGN', {
      active_campaigns_seen: allActive.map((c) => ({ id: c.id, name: c.name, objective: c.objective, effective_status: c.effective_status })),
      probe_details: activeFullpos.map((f) => ({
        id: f.campaign.id, name: f.campaign.name, objective: f.campaign.objective, evidence: f.evidence,
      })),
    });
  }
  if (plausible.length > 1 && !args.campaign) {
    throw new StopError('MULTIPLE_ACTIVE_FULLPOS_CAMPAIGNS', {
      candidates: plausible.map((f) => ({
        account_id: f.account.id,
        id: f.campaign.id,
        name: f.campaign.name,
        objective: f.campaign.objective,
        evidence: f.evidence,
      })),
    });
  }

  const chosen = args.campaign
    ? activeFullpos.find((f) => f.campaign.id === args.campaign)
    : plausible[0];
  if (!chosen) throw new StopError('CAMPAIGN_NOT_AMONG_ACTIVE_FULLPOS', { requested: args.campaign });

  const { campaign } = chosen;
  const account = chosen.account;
  const { adsets, ads } = await loadHierarchy(client, logger, campaign);

  /* Confirmation step required by the task: name alone is not enough. */
  const confirmation = isFullposCandidate(campaign, ads);
  chosen.evidence = {
    ...chosen.evidence,
    urlMatch: confirmation.urlMatch,
    adLinks: confirmation.adLinks,
    confirmed_by: confirmation.urlMatch ? 'name + destination URL' : 'name only',
  };
  chosen.ads_present = ads.length;
  if (confirmation.adLinks.length > 0 && !confirmation.urlMatch) {
    throw new StopError('DESTINATION_URL_MISMATCH', {
      campaign: { id: campaign.id, name: campaign.name },
      ad_links_found: confirmation.adLinks,
      expected_host: 'fullposcloud.fulltechrd.com',
    });
  }
  if (confirmation.adLinks.length === 0) {
    logger.warn('destination URL could not be read from the ad creative', { campaign_id: campaign.id });
  }

  const campaignInsights = await fetchInsights(client, logger, campaign.id, 'campaign', { extended: true });
  const adsetInsights = [];
  for (const s of adsets) adsetInsights.push({ adset_id: s.id, name: s.name, insights: await fetchInsights(client, logger, s.id, 'adset') });
  const adInsights = [];
  for (const a of ads) adInsights.push({ ad_id: a.id, name: a.name, insights: await fetchInsights(client, logger, a.id, 'ad') });

  /* ---- PHASE 6: pixel / dataset audit ---- */
  const pixelIds = new Set();
  for (const s of adsets) if (s.promoted_object?.pixel_id) pixelIds.add(s.promoted_object.pixel_id);
  for (const a of ads) {
    for (const spec of a.tracking_specs ?? []) {
      if (Array.isArray(spec) && spec.length >= 3 && String(spec[0]).includes('pixel')) {
        const val = spec[2];
        if (Array.isArray(val)) for (const v of val) pixelIds.add(String(v));
      }
    }
  }
  const pixelCandidates = new Set(pixelIds);
  for (const p of discovery.pixels_by_ad_account?.[account.id] ?? []) pixelCandidates.add(p.id);

  const pixelReports = [];
  const businessId = discovery.businesses?.[0]?.id ?? null;
  const PIXEL_FIELD_CANDIDATES = [
    'id,name,creation_time,last_fired_time,is_unavailable,owner_business,owner_ad_account,data_use_setting,is_created_by_business,enable_automatic_matching,automatic_matching_fields,first_party_cookie_status,can_proxy,code',
    'id,name,creation_time,last_fired_time,is_unavailable,owner_business,data_use_setting,is_created_by_business',
    'id,name,creation_time,last_fired_time',
  ];
  for (const id of pixelCandidates) {
    let detail = { ok: false, error: null };
    for (const fields of PIXEL_FIELD_CANDIDATES) {
      detail = await tryGet(client, logger, `pixel ${id}`, id, { fields });
      if (detail.ok) break;
    }
    const stats = await tryGet(client, logger, `pixel stats ${id}`, `${id}/stats`, { aggregation: 'event' });
    const assignedUsers = businessId
      ? await tryGet(client, logger, `pixel assigned_users ${id}`, `${id}/assigned_users`, { business: businessId, fields: 'id,name,tasks' })
      : { ok: false, error: 'no business id resolved' };

    // Event names actually received by this dataset, flattened with totals.
    const eventTotals = {};
    for (const bucket of stats.ok ? stats.data?.data ?? [] : []) {
      for (const ev of bucket.data ?? []) {
        eventTotals[ev.value] = (eventTotals[ev.value] ?? 0) + Number(ev.count ?? 0);
      }
    }
    pixelReports.push({
      id,
      used_by_adset_promoted_object: pixelIds.has(id),
      used_by_ad_account: true,
      detail: detail.ok ? detail.data : null,
      detail_error: detail.ok ? null : detail.error,
      event_stats: stats.ok ? stats.data : null,
      event_stats_error: stats.ok ? null : stats.error,
      event_totals: eventTotals,
      event_names_seen: Object.keys(eventTotals).sort(),
      registration_started_present: Object.prototype.hasOwnProperty.call(eventTotals, TARGET_EVENT),
      registration_started_count: eventTotals[TARGET_EVENT] ?? 0,
      assigned_users: assignedUsers.ok ? assignedUsers.data?.data ?? null : null,
      assigned_users_error: assignedUsers.ok ? null : assignedUsers.error,
    });
  }

  const baseline = {
    generated_at: iso(),
    graph_api_version: client.version,
    account: {
      id: account.id,
      name: account.name,
      account_status: account.account_status,
      currency: account.currency,
      time_zone: account.time_zone,
    },
    selection: {
      matched_by: chosen.evidence,
      accounts_scanned: accounts.map((a) => ({ id: a.id, name: a.name })),
      active_fullpos_candidates: plausible.length,
      active_campaigns_probed: activeFullpos.map((f) => ({
        account_id: f.account.id,
        id: f.campaign.id,
        name: f.campaign.name,
        objective: f.campaign.objective,
        effective_status: f.campaign.effective_status,
        ads_present: f.ads_present,
        plausible: f.plausible,
        evidence: f.evidence,
      })),
      all_active_campaigns: allActive.map((c) => ({
        account_id: c.account_id, id: c.id, name: c.name, objective: c.objective, effective_status: c.effective_status,
      })),
    },
    campaign,
    adsets,
    ads,
    insights: {
      campaign: campaignInsights,
      adsets: adsetInsights,
      ads: adInsights,
      user_reported_context: {
        spend_usd_approx: 4.76,
        landing_page_views_approx: 95,
        cost_per_lpv_usd_approx: 0.05,
        real_accounts_created_appyra: 1,
        note: 'Valores aportados por el negocio; NO sustituyen los datos de la API.',
      },
    },
    pixels: pixelReports,
    accounts_report: accountReports,
  };

  logger.writeJson('BASELINE_FULLPOS_ADS.json', baseline);
  logger.step('audit summary', {
    campaign_id: campaign.id,
    name: campaign.name,
    objective: campaign.objective,
    effective_status: campaign.effective_status,
    adsets: adsets.map((s) => ({
      id: s.id, name: s.name, optimization_goal: s.optimization_goal,
      destination_type: s.destination_type, daily_budget: s.daily_budget,
      billing_event: s.billing_event, bid_strategy: s.bid_strategy,
      promoted_object: s.promoted_object,
    })),
    ads: ads.map((a) => ({
      id: a.id, name: a.name, effective_status: a.effective_status,
      creative_id: a.creative?.id, video_id: a.creative?.video_id ?? null,
      link_url: a.creative?.link_url ?? a.creative?.object_story_spec?.link_data?.link ?? null,
    })),
    insights_campaign: campaignInsights.summary,
    pixels: pixelReports.map((p) => ({ id: p.id, name: p.detail?.name, last_fired_time: p.detail?.last_fired_time })),
  });
  return baseline;
}

/* ------------------------------------------------------------------ */
/* command: plan (PHASES 7, 9, 10, 11, 12, 13)                         */
/* ------------------------------------------------------------------ */

function buildPlan(ctx, baseline) {
  const { logger } = ctx;
  const campaign = baseline.campaign;
  const adset = baseline.adsets[0];
  const ad = baseline.ads[0];
  if (!adset || !ad) throw new StopError('BASELINE_INCOMPLETE', { adsets: baseline.adsets?.length ?? 0, ads: baseline.ads?.length ?? 0 });
  if (baseline.adsets.length > 1) {
    logger.warn('original campaign has more than one ad set; only the first is cloned', {
      adsets: baseline.adsets.map((s) => ({ id: s.id, name: s.name })),
    });
  }

  const pixelId = adset.promoted_object?.pixel_id ?? baseline.pixels?.find((p) => p.id)?.id ?? null;
  if (!pixelId) throw new StopError('ORIGINAL_ADSET_HAS_NO_PIXEL', { promoted_object: adset.promoted_object ?? null });
  const pixelSource = adset.promoted_object?.pixel_id
    ? 'adset.promoted_object'
    : 'account pixel (only one readable on this ad account)';

  /* Meta returns these inside `targeting` but they are read-only representations:
   * `age_range` is a suggestion artifact (the real values are age_min/age_max) and
   * `user_age_unknown` is a marker. Posting them back is rejected. Removing them
   * cannot change the audience; age_min/age_max are never touched. */
  const targeting = JSON.parse(JSON.stringify(adset.targeting ?? {}));
  const removedReadonlyTargeting = [];
  for (const key of READONLY_TARGETING_KEYS) {
    if (key in targeting) {
      delete targeting[key];
      removedReadonlyTargeting.push(key);
    }
  }

  const today = new Date().toISOString().slice(0, 10);
  const newCampaignName = `${NEW_CAMPAIGN_NAME_BASE} - ${today}`;

  const campaignPayload = {
    name: newCampaignName,
    objective: 'OUTCOME_LEADS',
    status: 'PAUSED',
    special_ad_categories: campaign.special_ad_categories ?? [],
    buying_type: campaign.buying_type ?? 'AUCTION',
  };
  if (campaign.special_ad_category_country) campaignPayload.special_ad_category_country = campaign.special_ad_category_country;
  if (campaign.daily_budget) campaignPayload.daily_budget = campaign.daily_budget;
  if (campaign.lifetime_budget) campaignPayload.lifetime_budget = campaign.lifetime_budget;

  /* With no campaign-level budget (ABO) Meta REQUIRES this flag on create
   * (error 4834011). Its value is mirrored from the original campaign — never
   * invented — otherwise budget behaviour could differ from the baseline. */
  const abo = !campaign.daily_budget && !campaign.lifetime_budget;
  if (abo) {
    if (typeof campaign.is_adset_budget_sharing_enabled !== 'boolean') {
      throw new StopError('ADSET_BUDGET_SHARING_FLAG_UNREADABLE', {
        original_campaign_id: campaign.id,
        read_value: campaign.is_adset_budget_sharing_enabled ?? null,
        note: 'Meta requires True/False on create for campaigns without campaign budget; the original value could not be read, refusing to guess.',
      });
    }
    campaignPayload.is_adset_budget_sharing_enabled = campaign.is_adset_budget_sharing_enabled;
  }

  const adsetPayload = {
    name: `${NEW_CAMPAIGN_NAME_BASE} - RD`,
    status: 'PAUSED',
    billing_event: adset.billing_event ?? 'IMPRESSIONS',
    optimization_goal: 'OFFSITE_CONVERSIONS',
    bid_strategy: adset.bid_strategy ?? 'LOWEST_COST_WITHOUT_CAP',
    destination_type: 'WEBSITE',
    promoted_object: {
      pixel_id: pixelId,
      custom_event_type: 'OTHER',
      custom_event_str: TARGET_EVENT,
    },
    targeting,
  };
  // Budget lives where the original had it (CBO vs ABO) — never duplicated.
  if (adset.daily_budget) adsetPayload.daily_budget = adset.daily_budget;
  if (adset.lifetime_budget) adsetPayload.lifetime_budget = adset.lifetime_budget;
  if (adset.attribution_spec) adsetPayload.attribution_spec = adset.attribution_spec;
  if (adset.pacing_type) adsetPayload.pacing_type = adset.pacing_type;
  if (adset.bid_constraints) adsetPayload.bid_constraints = adset.bid_constraints;
  if (adset.bid_amount) adsetPayload.bid_amount = adset.bid_amount;
  if (adset.frequency_control_specs) adsetPayload.frequency_control_specs = adset.frequency_control_specs;
  if (adset.daily_spend_cap) adsetPayload.daily_spend_cap = adset.daily_spend_cap;
  if (adset.use_new_app_click != null) adsetPayload.use_new_app_click = adset.use_new_app_click;

  const adPayload = {
    name: ad.name,
    status: 'PAUSED',
    creative: { creative_id: ad.creative?.id },
    // tracking_specs are intentionally not copied: they are per-object and Meta
    // derives them from the creative + promoted_object.
  };

  return {
    generated_at: iso(),
    graph_api_version: ctx.client.version,
    target_event: TARGET_EVENT,
    old: {
      campaign_id: campaign.id,
      adset_id: adset.id,
      ad_id: ad.id,
      creative_id: ad.creative?.id ?? null,
      creative_video_id: ad.creative?.video_id ?? null,
      story_video_id: ad.creative?.object_story_spec?.video_data?.video_id ?? null,
      page_id: creativePageId(ad.creative),
      instagram_user_id: creativeInstagramUserId(ad.creative),
      link_url: creativeLandingUrl(ad.creative),
      body: creativeBody(ad.creative),
      headline: creativeHeadline(ad.creative),
      call_to_action_type: creativeCallToAction(ad.creative),
      url_tags: ad.creative?.url_tags ?? null,
      objective: campaign.objective,
      optimization_goal: adset.optimization_goal,
      destination_type: adset.destination_type ?? null,
      billing_event: adset.billing_event ?? null,
      bid_strategy: adset.bid_strategy ?? null,
      attribution_spec: adset.attribution_spec ?? null,
      daily_budget: campaign.daily_budget ?? adset.daily_budget ?? null,
      budget_owner: campaign.daily_budget ? 'campaign' : adset.daily_budget ? 'adset' : null,
      effective_status: campaign.effective_status,
      status: campaign.status,
      pixel_id: pixelId,
      pixel_id_source: pixelSource,
    },
    new: {
      campaign: campaignPayload,
      adset: adsetPayload,
      ad: adPayload,
    },
    notes: {
      budget_copied_exactly: campaign.daily_budget ?? adset.daily_budget ?? null,
      targeting_copied_verbatim: true,
      budget_owner_mirrored: campaign.daily_budget ? 'campaign' : 'adset',
      is_adset_budget_sharing_enabled_mirrored: campaign.is_adset_budget_sharing_enabled ?? null,
      pixel_id_source: pixelSource,
      adset_had_no_promoted_object: !adset.promoted_object,
      readonly_targeting_keys_removed: removedReadonlyTargeting,
      targeting_age_min_max_untouched: { age_min: targeting.age_min, age_max: targeting.age_max },
    },
  };
}

async function cmdPlan(ctx) {
  const baseline = readJson('BASELINE_FULLPOS_ADS.json');
  if (!baseline) throw new Error('Run `audit` first (missing out/BASELINE_FULLPOS_ADS.json)');
  const plan = buildPlan(ctx, baseline);
  ctx.logger.writeJson('03-plan.json', plan);
  ctx.logger.step('plan ready (nothing written to Meta)', {
    new_campaign_name: plan.new.campaign.name,
    objective: plan.new.campaign.objective,
    budget: plan.new.adset.daily_budget ?? plan.new.campaign.daily_budget,
    optimization_goal: plan.new.adset.optimization_goal,
    destination_type: plan.new.adset.destination_type,
    event: TARGET_EVENT,
    pixel_id: plan.new.adset.promoted_object.pixel_id,
    creative_id: plan.new.ad.creative.creative_id,
    readonly_targeting_keys_removed: plan.notes.readonly_targeting_keys_removed,
  });
  return plan;
}

/* ------------------------------------------------------------------ */
/* idempotency helpers                                                 */
/* ------------------------------------------------------------------ */

async function findCampaignByName(client, logger, accountId, name) {
  const res = await fetchCampaignsForAccount(client, logger, accountId, {
    filtering: [{ field: 'name', operator: 'CONTAIN', value: NEW_CAMPAIGN_NAME_BASE }],
  });
  return res.find((c) => c.name === name) ?? null;
}

async function findAdsetsByCampaign(client, logger, campaignId) {
  return fetchAdsetsForCampaign(client, logger, campaignId);
}

async function findAdsByCampaign(client, logger, campaignId) {
  return fetchAdsForCampaign(client, logger, campaignId);
}

/* ------------------------------------------------------------------ */
/* command: create (PHASES 19, 11, 12, 13)                             */
/* ------------------------------------------------------------------ */

/** Creates a paused object, and on "invalid parameter" strips ONLY fields Meta
 *  explicitly names and ONLY when they are in the read-only allow list. */
async function createWithGuardedStrip(client, logger, endpoint, payload, { attempts = 6 } = {}) {
  const body = JSON.parse(JSON.stringify(payload));
  const stripped = [];
  for (let i = 0; i < attempts; i += 1) {
    try {
      const res = await client.post(endpoint, body);
      return { response: res, payload: body, stripped };
    } catch (err) {
      if (!(err instanceof GraphError)) throw err;
      const spec = err.blameFieldSpecs?.[0];
      const blamed = Array.isArray(spec) ? spec[spec.length - 1] : null;
      const messageBlame = /Invalid parameter:\s*([A-Za-z0-9_.]+)/.exec(err.message ?? '')?.[1] ?? null;
      const field = blamed ?? messageBlame;
      const rootField = field?.split('.')[0];
      if (rootField && STRIPPABLE_TARGETING_FIELDS.includes(rootField) && rootField in body) {
        delete body[rootField];
        stripped.push(rootField);
        logger.warn('stripped read-only field rejected by Meta', { endpoint, field: rootField, code: err.code, subcode: err.subcode });
        continue;
      }
      throw err;
    }
  }
  throw new StopError('CREATE_RETRY_EXHAUSTED', { endpoint, stripped });
}

async function cmdCreate(ctx, args) {
  const { client, logger } = ctx;
  const plan = readJson('03-plan.json');
  const baseline = readJson('BASELINE_FULLPOS_ADS.json');
  if (!plan || !baseline) throw new Error('Run `plan` first (missing out/03-plan.json)');

  const accountId = baseline.account.id;
  const result = { generated_at: iso(), graph_api_version: client.version, created: {}, reused: {}, errors: [] };

  /* --- campaign (idempotent by exact name) --- */
  let campaign = await findCampaignByName(client, logger, accountId, plan.new.campaign.name);
  if (campaign) {
    result.reused.campaign = campaign;
    logger.info('idempotency: campaign already exists, reusing', { id: campaign.id, name: campaign.name, status: campaign.status });
  } else {
    const created = await createWithGuardedStrip(client, logger, `${accountId}/campaigns`, plan.new.campaign);
    result.created.campaign = created.response;
    campaign = { id: created.response.id, name: plan.new.campaign.name };
    logger.info('campaign created (PAUSED)', { id: campaign.id, name: campaign.name, stripped: created.stripped });
    await new Promise((r) => setTimeout(r, 2000));
    campaign = await fetchCampaign(client, logger, campaign.id);
  }
  result.campaign = campaign;
  logger.writeJson('04-created.json', result);

  /* --- ad set --- */
  const existingAdsets = await findAdsetsByCampaign(client, logger, campaign.id);
  let adset = existingAdsets.find((s) => s.optimization_goal === 'OFFSITE_CONVERSIONS') ?? null;
  if (adset) {
    result.reused.adset = adset;
    logger.info('idempotency: ad set with OFFSITE_CONVERSIONS already exists, reusing', { id: adset.id, name: adset.name });
  } else {
    const payload = { ...plan.new.adset, campaign_id: campaign.id };
    if (campaign.daily_budget) delete payload.daily_budget; // CBO: budget belongs to the campaign
    const created = await createWithGuardedStrip(client, logger, `${accountId}/adsets`, payload);
    result.created.adset = created.response;
    logger.info('ad set created (PAUSED)', { id: created.response.id, stripped: created.stripped });
    await new Promise((r) => setTimeout(r, 2000));
    adset = await fetchAdset(client, logger, created.response.id);
  }
  result.adset = adset;
  logger.writeJson('04-created.json', result);

  /* --- ad (reuses the ORIGINAL creative_id) --- */
  const existingAds = await findAdsByCampaign(client, logger, campaign.id);
  let ad = existingAds.find((a) => a.creative?.id === plan.old.creative_id) ?? existingAds[0] ?? null;
  if (ad) {
    result.reused.ad = ad;
    logger.info('idempotency: ad already exists, reusing', { id: ad.id, name: ad.name });
  } else {
    try {
      const created = await createWithGuardedStrip(client, logger, `${accountId}/ads`, { ...plan.new.ad, adset_id: adset.id });
      result.created.ad = created.response;
      logger.info('ad created (PAUSED)', { id: created.response.id, stripped: created.stripped });
      await new Promise((r) => setTimeout(r, 2000));
      ad = await fetchAd(client, logger, created.response.id);
    } catch (err) {
      // Persist what DID get created so the state stays reportable and the retry
      // stays idempotent instead of leaving an undocumented partial hierarchy.
      result.partial = true;
      result.errors.push({
        step: 'ad',
        error: err instanceof GraphError ? err.toJSON() : { message: String(err.message) },
      });
      logger.writeJson('04-created.json', result);
      throw new StopError('AD_CREATE_FAILED', {
        campaign: { id: campaign.id, name: campaign.name, status: campaign.status },
        adset: { id: adset.id, name: adset.name, status: adset.status },
        ad: null,
        creative_id: plan.old.creative_id,
        page_id: plan.old.page_id,
        meta_error: err instanceof GraphError ? err.toJSON() : { message: String(err.message) },
      });
    }
  }
  result.ad = ad;

  result.creative_reused = ad.creative?.id === plan.old.creative_id;
  if (!result.creative_reused) {
    throw new StopError('CREATIVE_NOT_REUSED', {
      expected_creative_id: plan.old.creative_id,
      actual_creative_id: ad.creative?.id ?? null,
    });
  }

  logger.writeJson('04-created.json', result);
  logger.step('create summary', {
    campaign: { id: campaign.id, name: campaign.name, status: campaign.status, effective_status: campaign.effective_status },
    adset: { id: adset.id, name: adset.name, status: adset.status, optimization_goal: adset.optimization_goal, promoted_object: adset.promoted_object },
    ad: { id: ad.id, name: ad.name, status: ad.status, creative_id: ad.creative?.id },
    creative_reused: result.creative_reused,
  });
  return result;
}

/* ------------------------------------------------------------------ */
/* command: verify (PHASE 15)                                          */
/* ------------------------------------------------------------------ */

async function cmdVerify(ctx) {
  const { client, logger } = ctx;
  const created = readJson('04-created.json');
  const plan = readJson('03-plan.json');
  const baseline = readJson('BASELINE_FULLPOS_ADS.json');
  if (!created || !plan || !baseline) throw new Error('Run `create` first');

  const campaign = await fetchCampaign(client, logger, created.campaign.id);
  const adsets = await findAdsetsByCampaign(client, logger, campaign.id);
  const ads = await findAdsByCampaign(client, logger, campaign.id);
  const adset = adsets[0] ?? null;
  const ad = ads[0] ?? null;
  const creative = ad?.creative ?? null;

  const oldTargeting = JSON.stringify(baseline.adsets[0]?.targeting ?? {});
  const newTargeting = JSON.stringify(adset?.targeting ?? {});
  const normalize = (t) => {
    const clone = JSON.parse(JSON.stringify(t));
    // Meta may materialise defaults on the new object; compare semantically.
    return clone;
  };
  const targetingDiff = [];
  const readonlyTargetingDiff = [];
  const oldT = normalize(baseline.adsets[0]?.targeting ?? {});
  const newT = normalize(adset?.targeting ?? {});
  const keys = new Set([...Object.keys(oldT), ...Object.keys(newT)]);
  for (const k of keys) {
    const a = JSON.stringify(oldT[k]);
    const b = JSON.stringify(newT[k]);
    if (a === b) continue;
    if (READONLY_TARGETING_KEYS.includes(k)) {
      readonlyTargetingDiff.push({ key: k, old: oldT[k], new: newT[k], note: 'read-only representation, intentionally not posted' });
      continue;
    }
    targetingDiff.push({ key: k, old: oldT[k], new: newT[k] });
  }

  const newVideoIds = creativeVideoIds(creative);
  const campaignObjectId = campaign.daily_budget ?? adset?.daily_budget ?? null;
  const checks = {
    campaign_created: Boolean(campaign?.id),
    campaign_status: campaign.status,
    campaign_objective: campaign.objective,
    campaign_objective_is_leads: campaign.objective === 'OUTCOME_LEADS',
    adset_created: Boolean(adset?.id),
    adset_status: adset?.status ?? null,
    adset_optimization_goal: adset?.optimization_goal ?? null,
    adset_optimization_is_offsite_conversions: adset?.optimization_goal === 'OFFSITE_CONVERSIONS',
    adset_destination_type: adset?.destination_type ?? null,
    adset_billing_event: adset?.billing_event ?? null,
    adset_bid_strategy: adset?.bid_strategy ?? null,
    adset_promoted_object: adset?.promoted_object ?? null,
    adset_event_matches: adset?.promoted_object?.custom_event_str === TARGET_EVENT,
    adset_pixel_matches_original: (adset?.promoted_object?.pixel_id ?? null) === plan.old.pixel_id,
    budget_old: plan.old.daily_budget,
    budget_new: campaignObjectId,
    budget_same: campaignObjectId === plan.old.daily_budget,
    budget_owner: campaign.daily_budget ? 'campaign' : 'adset',
    attribution_old: baseline.adsets[0]?.attribution_spec ?? null,
    attribution_new: adset?.attribution_spec ?? null,
    targeting_identical: targetingDiff.length === 0,
    targeting_diff: targetingDiff,
    targeting_readonly_keys_excluded: readonlyTargetingDiff,

    /* Ad-dependent checks are only meaningful once an ad exists. Without one the
     * honest value is NOT_CREATED — reporting these as DIFFERENT would blame the
     * configuration for a missing object. */
    ad_exists: Boolean(ad?.id),
    ad_created: Boolean(ad?.id),
    ad_status: ad?.status ?? null,
    ad_effective_status: ad?.effective_status ?? null,
    creative_reused: creative?.id === plan.old.creative_id,
    video_same: newVideoIds.creative_video_id === plan.old.creative_video_id && newVideoIds.story_video_id === plan.old.story_video_id,
    video_ids_new: newVideoIds,
    body_same: creativeBody(creative) === plan.old.body,
    headline_same: creativeHeadline(creative) === plan.old.headline,
    cta_same: creativeCallToAction(creative) === plan.old.call_to_action_type,
    url_tags_same: (creative?.url_tags ?? null) === plan.old.url_tags,
    landing_url: creativeLandingUrl(creative),
    landing_url_same: creativeLandingUrl(creative) === plan.old.link_url,
    page_same: creativePageId(creative) === plan.old.page_id,
    instagram_same: creativeInstagramUserId(creative) === plan.old.instagram_user_id,
    issues_info: ad?.issues_info ?? [],
  };

  const artifact = {
    generated_at: iso(),
    graph_api_version: client.version,
    campaign,
    adsets,
    ads,
    checks,
    targeting_old_snapshot: oldTargeting,
    targeting_new_snapshot: newTargeting,
  };
  logger.writeJson('05-verify.json', artifact);
  logger.step('verify summary', checks);
  return artifact;
}

/* ------------------------------------------------------------------ */
/* command: compare (PHASE 16)                                         */
/* ------------------------------------------------------------------ */

async function cmdCompare(ctx) {
  const verify = readJson('05-verify.json');
  const plan = readJson('03-plan.json');
  if (!verify || !plan) throw new Error('Run `verify` first');
  const c = verify.checks;
  const adMissing = !verify.ads?.[0];
  const verdict = (same) => (adMissing ? 'NOT_CREATED' : same ? 'SAME' : 'DIFFERENT');
  const rows = [
    ['CAMPAIGN OBJECTIVE', plan.old.objective, verify.campaign.objective, plan.old.objective === verify.campaign.objective],
    ['OPTIMIZATION GOAL', plan.old.optimization_goal, c.adset_optimization_goal, plan.old.optimization_goal === c.adset_optimization_goal],
    ['DESTINATION TYPE', plan.old.destination_type ?? null, c.adset_destination_type, plan.old.destination_type === c.adset_destination_type],
    ['BILLING EVENT', plan.old.billing_event ?? null, c.adset_billing_event, (plan.old.billing_event ?? null) === c.adset_billing_event],
    ['BID STRATEGY', plan.old.bid_strategy ?? null, c.adset_bid_strategy, (plan.old.bid_strategy ?? null) === c.adset_bid_strategy],
    ['BUDGET', plan.old.daily_budget, c.budget_new, c.budget_same],
    ['BUDGET OWNER', plan.old.budget_owner, c.budget_owner, plan.old.budget_owner === c.budget_owner],
    ['ATTRIBUTION', JSON.stringify(plan.old.attribution_spec ?? null), JSON.stringify(c.attribution_new), JSON.stringify(plan.old.attribution_spec ?? null) === JSON.stringify(c.attribution_new)],
    ['TARGETING', 'baseline snapshot', c.targeting_identical ? 'identical' : 'differs', c.targeting_identical],
    ['PLACEMENTS', 'inherited from targeting (all placements)', c.targeting_identical ? 'identical' : 'see targeting_diff', c.targeting_identical],
    ['CREATIVE', plan.old.creative_id, verify.ads[0]?.creative?.id ?? null, c.creative_reused && !adMissing],
    ['VIDEO', JSON.stringify({ a: plan.old.creative_video_id, b: plan.old.story_video_id }), JSON.stringify(c.video_ids_new), c.video_same && !adMissing],
    ['COPY (body)', plan.old.body, creativeBody(verify.ads[0]?.creative), c.body_same && !adMissing],
    ['COPY (headline)', plan.old.headline, creativeHeadline(verify.ads[0]?.creative), c.headline_same && !adMissing],
    ['CTA', plan.old.call_to_action_type, creativeCallToAction(verify.ads[0]?.creative), c.cta_same && !adMissing],
    ['URL TAGS (UTM)', plan.old.url_tags, verify.ads[0]?.creative?.url_tags ?? null, c.url_tags_same && !adMissing],
    ['PAGE', plan.old.page_id, creativePageId(verify.ads[0]?.creative), c.page_same && !adMissing],
    ['INSTAGRAM', plan.old.instagram_user_id, creativeInstagramUserId(verify.ads[0]?.creative), c.instagram_same && !adMissing],
    ['URL', plan.old.link_url, c.landing_url, c.landing_url_same && !adMissing],
    ['PIXEL', plan.old.pixel_id, c.adset_promoted_object?.pixel_id ?? null, c.adset_pixel_matches_original],
    ['EVENT', null, c.adset_promoted_object?.custom_event_str ?? null, c.adset_event_matches],
  ];
  const artifact = {
    generated_at: iso(),
    rows: rows.map(([field, oldValue, newValue, same]) => ({ field, old: oldValue, new: newValue, same: Boolean(same) })),
    required_outcomes: {
      BUDGET: c.budget_same ? 'SAME' : 'DIFFERENT',
      BUDGET_OWNER: plan.old.budget_owner === c.budget_owner ? 'SAME' : 'DIFFERENT',
      TARGETING: c.targeting_identical ? 'SAME' : 'DIFFERENT',
      PLACEMENTS: c.targeting_identical ? 'SAME' : 'DIFFERENT',
      VIDEO: verdict(c.video_same),
      CREATIVE: verdict(c.creative_reused),
      URL: verdict(c.landing_url_same),
      COPY: verdict(c.body_same && c.headline_same),
      CTA: verdict(c.cta_same),
      PAGE: verdict(c.page_same),
      INSTAGRAM: verdict(c.instagram_same),
      URL_TAGS: verdict(c.url_tags_same),
      BILLING_EVENT: plan.old.billing_event === c.adset_billing_event ? 'SAME' : 'DIFFERENT',
      BID_STRATEGY: plan.old.bid_strategy === c.adset_bid_strategy ? 'SAME' : 'DIFFERENT',
      ATTRIBUTION: JSON.stringify(plan.old.attribution_spec ?? null) === JSON.stringify(c.attribution_new) ? 'SAME' : 'DIFFERENT',
      PIXEL: c.adset_pixel_matches_original ? 'SAME' : 'DIFFERENT',
      OPTIMIZATION: `${plan.old.optimization_goal} -> ${c.adset_optimization_goal}${c.adset_promoted_object?.custom_event_str ? ` (${c.adset_promoted_object.custom_event_str})` : ''}`,
    },
    ad_present: !adMissing,
    targeting_diff: c.targeting_diff,
  };
  ctx.logger.writeJson('06-comparison.json', artifact);
  ctx.logger.step('comparison', artifact.required_outcomes);
  return artifact;
}

/* ------------------------------------------------------------------ */
/* command: landing (PHASE 14)                                         */
/* ------------------------------------------------------------------ */

const normalizeText = (s) =>
  s
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/\\u00([0-9a-fA-F]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\s+/g, ' ')
    .toLowerCase();

async function fetchText(url, { maxBytes = 60 * 1024 * 1024 } = {}) {
  const res = await fetch(url, {
    redirect: 'follow',
    headers: { 'user-agent': 'fullpos-meta-migration/1.0 (+server-side-check)' },
  });
  const buf = Buffer.from(await res.arrayBuffer());
  return { status: res.status, ok: res.ok, finalUrl: res.url, contentType: res.headers.get('content-type'), bytes: buf.length, text: buf.subarray(0, maxBytes).toString('utf8') };
}

async function cmdLanding(ctx) {
  const { logger } = ctx;
  const artifact = { generated_at: iso(), url: LANDING_URL, required_strings: LANDING_REQUIRED_STRINGS, checked: [] };

  let html;
  try {
    html = await fetchText(LANDING_URL);
  } catch (err) {
    artifact.reachable = false;
    artifact.error = String(err.message);
    logger.writeJson('07-landing.json', artifact);
    logger.error('landing page unreachable', { error: String(err.message) });
    return artifact;
  }

  artifact.reachable = html.ok;
  artifact.http_status = html.status;
  artifact.final_url = html.finalUrl;
  artifact.content_type = html.contentType;
  artifact.html_bytes = html.bytes;

  const assets = [];
  const assetRegex = /(?:src|href)\s*=\s*["']([^"']+\.js(?:\?[^"']*)?)["']/gi;
  let m;
  while ((m = assetRegex.exec(html.text))) assets.push(m[1]);
  const extraAssets = ['/main.dart.js', '/flutter_bootstrap.js', '/flutter_service_worker.js'];

  const sources = [{ name: 'html', text: html.text }];
  for (const asset of [...new Set([...assets, ...extraAssets])]) {
    const url = new URL(asset, LANDING_URL).toString();
    try {
      const res = await fetchText(url);
      sources.push({ name: url.replace(LANDING_URL, '/'), text: res.text, bytes: res.bytes, status: res.status });
    } catch (err) {
      logger.warn('asset fetch failed', { asset: url, error: String(err.message) });
    }
  }

  for (const needle of LANDING_REQUIRED_STRINGS) {
    const target = normalizeText(needle);
    const found = [];
    for (const src of sources) {
      if (normalizeText(src.text).includes(target)) found.push(src.name);
    }
    artifact.checked.push({ string: needle, found: found.length > 0, in: found });
  }

  artifact.controls = LANDING_CONTROL_STRINGS.map((needle) => {
    const target = normalizeText(needle);
    const found = [];
    for (const src of sources) {
      if (normalizeText(src.text).includes(target)) found.push(src.name);
    }
    return { string: needle, found: found.length > 0, in: found };
  });
  artifact.search_pipeline_verified = artifact.controls.some((c) => c.found);

  artifact.all_required_strings_present = artifact.checked.every((c) => c.found);
  artifact.sources_scanned = sources.map((s) => ({ name: s.name, bytes: s.bytes ?? s.text.length }));

  /* Route checks: a 404 on the plain path is only acceptable if the hash form
   * serves the app, so both are probed and reported explicitly. */
  artifact.routes = [];
  for (const route of LANDING_ROUTES) {
    const plain = await (async () => {
      try {
        const r = await fetchText(new URL(route, LANDING_URL).toString(), { maxBytes: 4096 });
        return { url: new URL(route, LANDING_URL).toString(), http_status: r.status };
      } catch (err) {
        return { url: new URL(route, LANDING_URL).toString(), error: String(err.message) };
      }
    })();
    const hash = await (async () => {
      const hashUrl = `${LANDING_URL}#${route}`;
      try {
        const r = await fetchText(hashUrl, { maxBytes: 4096 });
        return { url: hashUrl, http_status: r.status };
      } catch (err) {
        return { url: hashUrl, error: String(err.message) };
      }
    })();
    artifact.routes.push({
      route,
      plain_path: plain,
      hash_path: hash,
      pass: plain.http_status === 200 || hash.http_status === 200,
    });
  }
  artifact.all_routes_pass = artifact.routes.every((r) => r.pass);
  logger.writeJson('07-landing.json', artifact);
  logger.step('landing check', {
    reachable: artifact.reachable,
    http_status: artifact.http_status,
    search_pipeline_verified: artifact.search_pipeline_verified,
    controls: artifact.controls.map((c) => `${c.string}: ${c.found ? 'FOUND' : 'NOT FOUND'}`),
    required: artifact.checked.map((c) => `${c.string}: ${c.found ? 'FOUND' : 'NOT FOUND'}${c.in.length ? ` (${c.in.join(',')})` : ''}`),
    routes: artifact.routes.map((r) => `${r.route}: plain=${r.plain_path.http_status ?? 'ERR'} hash=${r.hash_path.http_status ?? 'ERR'} -> ${r.pass ? 'PASS' : 'FAIL'}`),
    production_ready: Boolean(artifact.reachable && artifact.all_required_strings_present && artifact.all_routes_pass),
  });
  return artifact;
}

/* ------------------------------------------------------------------ */
/* command: permissions (read-only diagnostics for a write denial)      */
/* ------------------------------------------------------------------ */

async function cmdPermissions(ctx, args) {
  const { client, logger } = ctx;
  const discovery = readJson('02-discovery.json');
  const baseline = readJson('BASELINE_FULLPOS_ADS.json');
  const out = { generated_at: iso(), graph_api_version: client.version, probes: {} };

  const businessIds = (discovery?.businesses ?? []).map((b) => b.id);
  const accountIds = (discovery?.ad_accounts ?? []).map((a) => a.id);
  const focus = args.account ?? baseline?.account?.id ?? accountIds[accountIds.length - 1] ?? null;

  const probes = [
    ['me', 'me', { fields: 'id,name' }],
    ['me/assigned_ad_accounts', 'me/assigned_ad_accounts', { fields: 'id,name,account_status,currency' }],
    ['me/adaccounts', 'me/adaccounts', { fields: 'id,name,account_status' }],
    ['me/permissions', 'me/permissions', {}],
  ];
  for (const id of businessIds) {
    probes.push([`business ${id}`, id, { fields: 'id,name,verification_status' }]);
    probes.push([`assigned_users of business ${id}`, `${id}/assigned_users`, { fields: 'id,name,tasks' }]);
    probes.push([`owned_ad_accounts of business ${id}`, `${id}/owned_ad_accounts`, { fields: 'id,name,account_status' }]);
  }
  if (focus) {
    probes.push([`account ${focus}`, focus, { fields: 'id,name,account_status,currency,owner,business,capabilities,funding_source_details,is_prepay_account,disable_reason' }]);
    probes.push([`account ${focus} users`, `${focus}/users`, { fields: 'id,name,tasks' }]);
    for (const b of businessIds) {
      probes.push([
        `assigned_users of account ${focus}`,
        `${focus}/assigned_users`,
        { business: b, fields: 'id,name,tasks,permitted_tasks' },
      ]);
    }
  }

  for (const [label, endpoint, params] of probes) {
    const res = await tryGet(client, logger, `probe ${label}`, endpoint, params);
    out.probes[label] = res.ok ? res.data : { error: res.error };
  }

  out.analysis = {
    ad_account_management_grant_target_ids:
      (readJson('01-preflight.json')?.token?.granular_scopes ?? [])
        .filter((g) => g.scope === 'ads_management')
        .flatMap((g) => g.target_ids ?? []),
    focus_account: focus,
    focus_account_is_assigned_to_this_token: null,
  };
  const assigned = out.probes['me/assigned_ad_accounts'];
  if (assigned && Array.isArray(assigned.data)) {
    out.analysis.assigned_ad_accounts = assigned.data.map((a) => a.id);
    out.analysis.focus_account_is_assigned_to_this_token = assigned.data.some((a) => a.id === focus);
  }

  logger.writeJson('11-permissions.json', out);
  logger.step('permission diagnostics', {
    focus_account: focus,
    assigned_ad_accounts: out.analysis.assigned_ad_accounts ?? 'unreadable',
    focus_assigned: out.analysis.focus_account_is_assigned_to_this_token,
    ads_management_grant_target_ids: out.analysis.ad_account_management_grant_target_ids,
  });
  return out;
}

/* ------------------------------------------------------------------ */
/* command: page-check (page-level advertiser permission diagnostics)   */
/* ------------------------------------------------------------------ */

async function cmdPageCheck(ctx) {
  const { client, logger } = ctx;
  const discovery = readJson('02-discovery.json');
  const baseline = readJson('BASELINE_FULLPOS_ADS.json');
  const plan = readJson('03-plan.json');
  const pageId =
    plan?.old?.page_id ??
    baseline?.ads?.[0]?.creative?.object_story_spec?.page_id ??
    null;
  const businessIds = (discovery?.businesses ?? []).map((b) => b.id);
  const out = { generated_at: iso(), graph_api_version: client.version, page_id: pageId, probes: {} };

  const probes = [
    ['me/accounts (pages this token can act on)', 'me/accounts', { fields: 'id,name,tasks,instagram_business_account{id,username}' }],
  ];
  if (pageId) {
    probes.push([
      `page ${pageId}`,
      pageId,
      { fields: 'id,name,link,category,is_published,verification_status,username,instagram_business_account{id,username}' },
    ]);
  }
  for (const b of businessIds) {
    probes.push([`owned_pages of ${b}`, `${b}/owned_pages`, { fields: 'id,name' }]);
    probes.push([`client_pages of ${b}`, `${b}/client_pages`, { fields: 'id,name' }]);
    if (pageId) {
      probes.push([
        `assigned_users of page ${pageId}`,
        `${pageId}/assigned_users`,
        { business: b, fields: 'id,name,tasks,permitted_tasks' },
      ]);
    }
  }

  for (const [label, endpoint, params] of probes) {
    const res = await tryGet(client, logger, `probe ${label}`, endpoint, params);
    out.probes[label] = res.ok ? res.data : { error: res.error };
  }

  const accounts = out.probes['me/accounts (pages this token can act on)'];
  const tokenPages = Array.isArray(accounts?.data) ? accounts.data : [];
  out.analysis = {
    page_in_token_accounts: pageId ? tokenPages.some((p) => p.id === pageId) : null,
    token_pages: tokenPages.map((p) => ({ id: p.id, name: p.name, tasks: p.tasks ?? [] })),
    page_owned_by_business: businessIds.map((b) => ({
      business_id: b,
      in_owned_pages: (out.probes[`owned_pages of ${b}`]?.data ?? []).some((p) => p.id === pageId),
      in_client_pages: (out.probes[`client_pages of ${b}`]?.data ?? []).some((p) => p.id === pageId),
    })),
  };

  logger.writeJson('13-page-check.json', out);
  logger.step('page permission diagnostics', {
    page_id: pageId,
    page_in_token_accounts: out.analysis.page_in_token_accounts,
    token_pages: out.analysis.token_pages,
    page_owned_by_business: out.analysis.page_owned_by_business,
  });
  return out;
}

/* ------------------------------------------------------------------ */
/* command: cutover (PHASE 17)                                         */
/* ------------------------------------------------------------------ */

async function setStatus(client, logger, objectId, status) {
  const res = await client.post(objectId, { status });
  logger.info('status update', { object_id: objectId, requested: status, response: res });
  await new Promise((r) => setTimeout(r, 1500));
  return res;
}

async function readCampaign(client, id, logger = activeLogger) {
  return fetchCampaign(client, logger, id);
}

async function cmdCutover(ctx, args) {
  const { client, logger } = ctx;
  const created = readJson('04-created.json');
  const compare = readJson('06-comparison.json');
  const landing = readJson('07-landing.json');
  const baseline = readJson('BASELINE_FULLPOS_ADS.json');
  if (!created || !compare || !baseline) throw new Error('Run `create`, `verify` and `compare` first');

  const out = { generated_at: iso(), steps: [], rollback: { required: false, executed: false } };
  const oldCampaignId = baseline.campaign.id;
  const newCampaignId = created.campaign.id;
  const newAdsetId = created.adset.id;
  const newAdId = created.ad.id;

  const record = (step, data) => {
    out.steps.push({ at: iso(), step, ...data });
    logger.info(`cutover: ${step}`, data);
  };

  const oldBefore = await readCampaign(client, oldCampaignId);
  out.old_before = { id: oldBefore.id, name: oldBefore.name, status: oldBefore.status, effective_status: oldBefore.effective_status };

  /* Gate 1 — landing must be live in PRODUCTION (copy + register/login routes) */
  const landingReady = Boolean(landing?.all_required_strings_present) && (landing?.all_routes_pass ?? true);
  if (!landingReady) {
    record('GATE_LANDING_FAILED', {
      landing: landing?.checked ?? null,
      routes: landing?.routes ?? null,
    });
    out.final_status = 'WAITING_FOR_LANDING_DEPLOYMENT';
    logger.writeJson('08-cutover.json', out);
    return out;
  }

  /* Gate 2 — replacement verified */
  const required = compare.required_outcomes;
  const strictlySame = ['BUDGET', 'TARGETING', 'PLACEMENTS', 'VIDEO', 'CREATIVE', 'URL', 'COPY', 'CTA', 'PAGE', 'INSTAGRAM', 'URL_TAGS', 'BILLING_EVENT', 'BID_STRATEGY', 'ATTRIBUTION', 'PIXEL'];
  const failing = strictlySame.filter((k) => required[k] !== undefined && required[k] !== 'SAME');
  if (failing.length) {
    record('GATE_COMPARISON_FAILED', { required_outcomes: required, failing });
    out.final_status = 'BLOCKED';
    logger.writeJson('08-cutover.json', out);
    return out;
  }
  record('GATES_PASSED', { required_outcomes: required });

  /* Step 1 — activate the replacement FIRST, so there is never a zero-advertising window. */
  try {
    await setStatus(client, logger, newCampaignId, 'ACTIVE');
    await setStatus(client, logger, newAdsetId, 'ACTIVE');
    await setStatus(client, logger, newAdId, 'ACTIVE');
  } catch (err) {
    record('NEW_ACTIVATION_FAILED', { error: err.toJSON?.() ?? String(err.message) });
    out.rollback.required = true;
    // Nothing was paused yet: just revert the replacement to PAUSED.
    for (const id of [newAdId, newAdsetId, newCampaignId]) {
      try { await setStatus(client, logger, id, 'PAUSED'); } catch { /* best effort */ }
    }
    out.rollback.executed = true;
    out.final_status = 'ROLLED_BACK';
    logger.writeJson('08-cutover.json', out);
    return out;
  }

  const newCampaign = await readCampaign(client, newCampaignId);
  const newAd = await fetchAd(client, logger, newAdId);
  const newAdset = await fetchAdset(client, logger, newAdsetId);
  record('NEW_ACTIVATED', {
    campaign: { id: newCampaign.id, status: newCampaign.status, effective_status: newCampaign.effective_status },
    adset: { id: newAdset.id, status: newAdset.status, effective_status: newAdset.effective_status },
    ad: { id: newAd.id, status: newAd.status, effective_status: newAd.effective_status, issues_info: newAd.issues_info ?? [] },
  });

  const deliverable = newAd.effective_status === 'ACTIVE' && newCampaign.effective_status === 'ACTIVE';
  if (!deliverable) {
    // Review pending: keep the ORIGINAL running (no advertising gap) and park the
    // replacement in PAUSED so no duplicate spend can happen.
    record('PENDING_REVIEW', {
      new_ad_effective_status: newAd.effective_status,
      new_campaign_effective_status: newCampaign.effective_status,
      action: 'replacement re-paused; original left ACTIVE',
    });
    for (const id of [newAdId, newAdsetId, newCampaignId]) {
      try { await setStatus(client, logger, id, 'PAUSED'); } catch { /* best effort */ }
    }
    out.new_after = { status: 'PAUSED', effective_status: (await readCampaign(client, newCampaignId)).effective_status };
    out.old_after = { status: (await readCampaign(client, oldCampaignId)).status };
    out.final_status = 'NEW_CAMPAIGN_PENDING_REVIEW';
    logger.writeJson('08-cutover.json', out);
    return out;
  }

  /* Step 2 — replacement is deliverable: pause the original campaign only. */
  try {
    await setStatus(client, logger, oldCampaignId, 'PAUSED');
    const oldAfter = await readCampaign(client, oldCampaignId);
    record('OLD_PAUSED', { id: oldAfter.id, status: oldAfter.status, effective_status: oldAfter.effective_status });
    if (oldAfter.status !== 'PAUSED') throw new StopError('OLD_PAUSE_NOT_CONFIRMED', { status: oldAfter.status });
  } catch (err) {
    record('OLD_PAUSE_FAILED', { error: err.toJSON?.() ?? String(err.message) });
    out.rollback.required = true;
    try {
      await setStatus(client, logger, oldCampaignId, 'ACTIVE');
      const restored = await readCampaign(client, oldCampaignId);
      record('ROLLBACK_OLD_RESTORED', { status: restored.status, effective_status: restored.effective_status });
      out.rollback.executed = restored.status === 'ACTIVE';
    } catch (rbErr) {
      record('ROLLBACK_FAILED', { error: rbErr.toJSON?.() ?? String(rbErr.message) });
    }
    for (const id of [newAdId, newAdsetId, newCampaignId]) {
      try { await setStatus(client, logger, id, 'PAUSED'); } catch { /* best effort */ }
    }
    out.final_status = out.rollback.executed ? 'ROLLED_BACK' : 'BLOCKED';
    logger.writeJson('08-cutover.json', out);
    return out;
  }

  out.old_after = await readCampaign(client, oldCampaignId);
  out.new_after = await readCampaign(client, newCampaignId);
  out.new_ad_after = await fetchAd(client, logger, newAdId);
  out.final_status = 'CUTOVER_COMPLETE';
  logger.writeJson('08-cutover.json', out);
  logger.step('cutover complete', {
    old: { id: out.old_after.id, status: out.old_after.status, effective_status: out.old_after.effective_status },
    new: { id: out.new_after.id, status: out.new_after.status, effective_status: out.new_after.effective_status },
  });
  return out;
}

/* ------------------------------------------------------------------ */
/* command: rollback                                                   */
/* ------------------------------------------------------------------ */

async function cmdRollback(ctx) {
  const { client, logger } = ctx;
  const baseline = readJson('BASELINE_FULLPOS_ADS.json');
  const created = readJson('04-created.json');
  if (!baseline) throw new Error('Run `audit` first');
  const out = { generated_at: iso(), steps: [] };

  if (created?.campaign?.id) {
    await setStatus(client, logger, created.ad.id, 'PAUSED');
    await setStatus(client, logger, created.adset.id, 'PAUSED');
    await setStatus(client, logger, created.campaign.id, 'PAUSED');
    out.new_campaign = { id: created.campaign.id, status: (await readCampaign(client, created.campaign.id)).status };
  }
  await setStatus(client, logger, baseline.campaign.id, 'ACTIVE');
  const restored = await readCampaign(client, baseline.campaign.id);
  out.old_campaign = { id: restored.id, status: restored.status, effective_status: restored.effective_status };
  out.ok = restored.status === 'ACTIVE';
  logger.writeJson('09-rollback.json', out);
  logger.step('rollback done', out);
  return out;
}

/* ------------------------------------------------------------------ */
/* command: status                                                     */
/* ------------------------------------------------------------------ */

async function cmdStatus(ctx) {
  const { client, logger } = ctx;
  const baseline = readJson('BASELINE_FULLPOS_ADS.json');
  const created = readJson('04-created.json');
  const out = { generated_at: iso(), graph_api_version: client.version, old: null, new: null };

  if (baseline) {
    const c = await readCampaign(client, baseline.campaign.id);
    const adsets = await findAdsetsByCampaign(client, logger, baseline.campaign.id);
    const ads = await findAdsByCampaign(client, logger, baseline.campaign.id);
    out.old = {
      campaign: { id: c.id, name: c.name, objective: c.objective, status: c.status, effective_status: c.effective_status },
      adsets: adsets.map((s) => ({ id: s.id, status: s.status, effective_status: s.effective_status, optimization_goal: s.optimization_goal })),
      ads: ads.map((a) => ({ id: a.id, status: a.status, effective_status: a.effective_status })),
    };
  }
  if (created?.campaign?.id) {
    const c = await readCampaign(client, created.campaign.id);
    const adsets = await findAdsetsByCampaign(client, logger, created.campaign.id);
    const ads = await findAdsByCampaign(client, logger, created.campaign.id);
    out.new = {
      campaign: { id: c.id, name: c.name, objective: c.objective, status: c.status, effective_status: c.effective_status },
      adsets: adsets.map((s) => ({ id: s.id, status: s.status, effective_status: s.effective_status, optimization_goal: s.optimization_goal, promoted_object: s.promoted_object })),
      ads: ads.map((a) => ({ id: a.id, status: a.status, effective_status: a.effective_status, issues_info: a.issues_info ?? [] })),
    };
  }
  logger.writeJson('10-status.json', out);
  logger.step('status', out);
  return out;
}

/** Proof that a failed run left no partial objects behind. */
async function cmdVerifyNoop(ctx) {
  const { client, logger } = ctx;
  const discovery = readJson('02-discovery.json');
  const out = { generated_at: iso(), graph_api_version: client.version, searched_name: NEW_CAMPAIGN_NAME_BASE, accounts: [] };
  for (const account of discovery?.ad_accounts ?? []) {
    const res = await tryGet(client, logger, `lookup ${account.id}`, `${account.id}/campaigns`, {
      fields: 'id,name,objective,status,effective_status,daily_budget',
      filtering: [{ field: 'name', operator: 'CONTAIN', value: NEW_CAMPAIGN_NAME_BASE.split(' - ')[0] }],
    });
    out.accounts.push({
      account_id: account.id,
      ok: res.ok,
      matches: res.ok ? res.data?.data ?? [] : null,
      error: res.ok ? null : res.error,
    });
  }
  out.replacement_exists = out.accounts.some((a) => (a.matches ?? []).length > 0);
  logger.writeJson('12-noop-check.json', out);
  logger.step('no-op verification (nothing was created)', { replacement_exists: out.replacement_exists, accounts: out.accounts.map((a) => ({ id: a.account_id, matches: (a.matches ?? []).length })) });
  return out;
}

/* ------------------------------------------------------------------ */
/* main                                                                */
/* ------------------------------------------------------------------ */

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const command = args._[0];
  const supported = ['preflight', 'discover', 'campaigns', 'audit', 'plan', 'create', 'verify', 'compare', 'landing', 'cutover', 'rollback', 'status', 'permissions', 'page-check', 'noop-check'];
  if (!command || !supported.includes(command)) {
    console.log(`usage: node scripts/meta-ads/meta.mjs <${supported.join('|')}> [--account act_X] [--campaign ID]`);
    process.exit(command ? 2 : 0);
  }

  const handlers = {
    preflight: cmdPreflight,
    discover: cmdDiscover,
    campaigns: cmdCampaigns,
    audit: cmdAudit,
    plan: cmdPlan,
    create: cmdCreate,
    verify: cmdVerify,
    compare: cmdCompare,
    landing: cmdLanding,
    cutover: cmdCutover,
    rollback: cmdRollback,
    status: cmdStatus,
    permissions: cmdPermissions,
    'page-check': cmdPageCheck,
    'noop-check': cmdVerifyNoop,
  };

  let ctx = null;
  try {
    ctx = await bootstrap({ commandName: `meta-${command}`, requireAdsManagement: command !== 'status' });
    await handlers[command](ctx, args);
    ctx.logger.info(`command ${command} finished`, { graph_calls: ctx.client.calls, out_dir: 'scripts/meta-ads/out' });
  } catch (err) {
    // Bootstrap failures must be reported sanitized, never as a raw crash.
    let logger = ctx?.logger;
    if (!logger) {
      let redact = (s) => String(s);
      try {
        redact = makeRedactor(loadSecrets());
      } catch { /* env unreadable: fall back to a plain stringifier */ }
      logger = new Logger(redact, `meta-${command}`);
    }
    if (err instanceof StopError) {
      logger.error(`STOP: ${err.reason}`, err.details);
      logger.writeJson(`stop-${command}.json`, {
        generated_at: iso(),
        command,
        stop_reason: err.reason,
        details: err.details ?? null,
      });
      process.exitCode = 3;
      return;
    }
    const payload = err instanceof GraphError ? err.toJSON() : { message: String(err.message) };
    logger.error(`command ${command} failed`, payload);
    process.exitCode = 1;
  }
}

main();
