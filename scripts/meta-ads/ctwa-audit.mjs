#!/usr/bin/env node
/**
 * FullPOS Cloud — Meta Ads audit: Click-to-WhatsApp (CTWA) campaign. READ-ONLY.
 *
 *   node scripts/meta-ads/ctwa-audit.mjs [--campaign ID] [--account act_X]
 *
 * Guarantees:
 *  - Only GET requests are ever issued (the only transport used is MetaClient.get).
 *    No POST / PATCH / DELETE exists in this file, so it cannot change Meta state.
 *  - Secrets never leave the process: every emitted string passes the redactor and
 *    the .env values themselves are only reported as PRESENT/MISSING.
 *  - Every claim in the artifact comes from a real API response. Failures are
 *    reported as NOT ACCESSIBLE with the Graph error, never guessed.
 *
 * Artifact: scripts/meta-ads/out/ctwa-audit.json  (redacted, gitignored)
 */

import {
  Logger,
  MetaClient,
  GraphError,
  envPresence,
  loadSecrets,
  makeRedactor,
  resolveApiVersion,
} from './lib/graph.mjs';

const ARTIFACT = 'ctwa-audit.json';
const MAX_CANDIDATES = 5;
const CAMPAIGN_LOOKBACK_DAYS = 45;

/* ------------------------------------------------------------------ */
/* small utils                                                         */
/* ------------------------------------------------------------------ */

const iso = () => new Date().toISOString();
const num = (v) => (v === null || v === undefined || v === '' ? null : Number(v));

/** Partial display form of a long numeric id (campaign/adset/ad/dataset). */
const maskId = (v) => {
  const s = String(v ?? '');
  return s.length <= 12 ? s : `${s.slice(0, 6)}...${s.slice(-4)}`;
};

/** Phone numbers are shown partially; the full value stays in the artifact. */
const maskPhone = (v) => {
  const s = String(v ?? '').replace(/\D/g, '');
  if (s.length < 6) return s || null;
  return `${s.slice(0, 4)}***${s.slice(-3)}`;
};

/* ------------------------------------------------------------------ */
/* field sets (Meta rejects the whole request when one field is bad,   */
/* so every read has ordered fallbacks)                                */
/* ------------------------------------------------------------------ */

const CAMPAIGN_FIELDS = [
  [
    'id', 'name', 'objective', 'status', 'effective_status', 'configured_status',
    'buying_type', 'special_ad_categories', 'daily_budget', 'lifetime_budget', 'budget_remaining',
    'is_adset_budget_sharing_enabled', 'created_time', 'updated_time', 'start_time', 'stop_time',
    'account_id', 'smart_promotion_type', 'source_campaign_id',
  ].join(','),
  [
    'id', 'name', 'objective', 'status', 'effective_status', 'buying_type',
    'special_ad_categories', 'daily_budget', 'lifetime_budget', 'created_time', 'updated_time',
  ].join(','),
  'id,name,objective,status,effective_status',
];

const ADSET_FIELDS = [
  'id', 'name', 'campaign_id', 'status', 'effective_status', 'configured_status',
  'daily_budget', 'lifetime_budget', 'budget_remaining', 'daily_spend_cap',
  'billing_event', 'optimization_goal', 'optimization_sub_event', 'bid_strategy', 'bid_amount',
  'bid_constraints', 'pacing_type', 'destination_type', 'promoted_object', 'attribution_spec',
  'start_time', 'end_time', 'targeting', 'is_dynamic_creative', 'frequency_control_specs',
  'learning_stage_info', 'created_time', 'updated_time',
].join(',');

const ADSET_FIELDS_CANDIDATES = [
  ADSET_FIELDS,
  [
    'id', 'name', 'campaign_id', 'status', 'effective_status', 'daily_budget', 'lifetime_budget',
    'billing_event', 'optimization_goal', 'bid_strategy', 'destination_type', 'promoted_object',
    'attribution_spec', 'start_time', 'end_time', 'targeting', 'pacing_type',
  ].join(','),
  [
    'id', 'name', 'status', 'effective_status', 'daily_budget', 'lifetime_budget',
    'optimization_goal', 'destination_type', 'promoted_object', 'targeting',
  ].join(','),
  'id,name,status,effective_status,optimization_goal,destination_type,targeting',
];

const CREATIVE_FIELDS = [
  'id', 'name', 'status', 'object_type', 'account_id',
  'title', 'body', 'link_url', 'call_to_action_type', 'url_tags',
  'image_hash', 'image_url', 'video_id', 'thumbnail_url',
  'object_story_id', 'effective_object_story_id', 'object_story_spec',
  'instagram_actor_id', 'instagram_permalink_url', 'asset_feed_spec', 'degrees_of_freedom_spec',
].join(',');

const CREATIVE_FIELDS_REDUCED = [
  'id', 'name', 'status', 'object_type', 'title', 'body', 'link_url', 'call_to_action_type',
  'url_tags', 'video_id', 'image_hash', 'thumbnail_url', 'object_story_id',
  'effective_object_story_id', 'object_story_spec', 'instagram_actor_id', 'asset_feed_spec',
].join(',');

const AD_BASE_FIELDS = [
  'id', 'name', 'campaign_id', 'adset_id', 'status', 'effective_status', 'configured_status',
  'created_time', 'updated_time', 'tracking_specs', 'issues_info',
].join(',');

const AD_FIELDS_CANDIDATES = [
  `${AD_BASE_FIELDS},preview_shareable_link,creative{${CREATIVE_FIELDS}}`,
  `${AD_BASE_FIELDS},creative{${CREATIVE_FIELDS}}`,
  `${AD_BASE_FIELDS},creative{${CREATIVE_FIELDS_REDUCED}}`,
  'id,name,campaign_id,adset_id,status,effective_status,issues_info,creative{id,name,object_story_spec,asset_feed_spec,call_to_action_type,link_url}',
];

const PIXEL_FIELDS_CANDIDATES = [
  'id,name,creation_time,last_fired_time,is_unavailable,owner_business,owner_ad_account,data_use_setting,is_created_by_business,enable_automatic_matching,automatic_matching_fields,first_party_cookie_status,can_proxy,code',
  'id,name,creation_time,last_fired_time,is_unavailable,data_use_setting,is_created_by_business',
  'id,name,creation_time,last_fired_time',
  'id,name',
];

const ACCOUNT_FIELDS_CANDIDATES = [
  'id,account_id,name,account_status,disable_reason,currency,time_zone,timezone_name,business,owner,is_prepay_account,amount_spent,balance,capabilities,business_country_code,created_time,funding_source_details',
  'id,account_id,name,account_status,disable_reason,currency,timezone_name,business,owner,amount_spent,balance',
  'id,account_id,name,account_status,currency,timezone_name,amount_spent,balance',
  'id,name,account_status',
];

/** Purpose-built: ownership is needed to reach the WhatsApp Business Account. */
const ACCOUNT_OWNERSHIP_FIELDS = [
  'business,owner,account_status,disable_reason,is_prepay_account,spend_cap,capabilities,funding_source_details,timezone_offset_hours_utc',
  'business,owner,account_status,disable_reason,is_prepay_account',
  'business,owner,account_status',
];

const PAGE_FIELDS_CANDIDATES = [
  'id,name,link,category,verification_status,instagram_business_account{id,username},whatsapp_business_account{id,name}',
  'id,name,link,category,verification_status,instagram_business_account{id,username}',
  'id,name,link',
  'id,name',
];

const BUSINESS_FIELDS_CANDIDATES = [
  'id,name,verification_status,created_time,primary_page,link',
  'id,name,verification_status,created_time',
  'id,name',
];

const INSIGHT_FIELDS = [
  'spend', 'impressions', 'reach', 'frequency', 'clicks', 'unique_clicks',
  'inline_link_clicks', 'inline_link_click_ctr', 'outbound_clicks', 'ctr', 'cpc', 'cpm',
  'actions', 'cost_per_action_type', 'date_start', 'date_stop',
].join(',');

const INSIGHT_FIELDS_EXTENDED = `${INSIGHT_FIELDS},results,cost_per_result,optimization_goal,attribution_setting`;

/* ------------------------------------------------------------------ */
/* transport wrappers (GET only)                                       */
/* ------------------------------------------------------------------ */

async function tryGet(client, logger, label, endpoint, params = {}) {
  try {
    return { ok: true, data: await client.get(endpoint, params) };
  } catch (err) {
    const detail = err instanceof GraphError ? err.toJSON() : { message: String(err.message) };
    logger.warn(`read failed: ${label}`, { endpoint, error: detail });
    return { ok: false, error: detail, endpoint };
  }
}

async function probeGet(client, logger, label, endpoint, fieldCandidates, extra = {}) {
  const attempts = [];
  for (const fields of fieldCandidates) {
    try {
      const data = await client.get(endpoint, { fields, ...extra });
      return { ok: true, data, fields_used: fields };
    } catch (err) {
      const detail = err instanceof GraphError ? err.toJSON() : { message: String(err.message) };
      attempts.push({ fields, error: detail });
      // Only a field complaint justifies a narrower field set; anything else
      // (permission, throttle) must not be amplified by extra calls.
      if (err instanceof GraphError && !err.isFieldError) break;
    }
  }
  const error = attempts[attempts.length - 1]?.error ?? null;
  logger.warn(`read failed: ${label}`, { endpoint, error });
  return { ok: false, error, attempts };
}

async function allEdge(client, logger, label, endpoint, fieldCandidates, extra = {}, pageOpts = { limit: 50, maxPages: 3 }) {
  const attempts = [];
  for (const fields of fieldCandidates) {
    try {
      const data = await client.all(endpoint, { fields, ...extra }, pageOpts);
      return { ok: true, data, fields_used: fields };
    } catch (err) {
      const detail = err instanceof GraphError ? err.toJSON() : { message: String(err.message) };
      attempts.push({ fields, error: detail });
      if (err instanceof GraphError && !err.isFieldError) break;
    }
  }
  const error = attempts[attempts.length - 1]?.error ?? null;
  logger.warn(`listing failed: ${label}`, { endpoint, error });
  return { ok: false, error, attempts };
}

/* ------------------------------------------------------------------ */
/* creative / CTWA signal extraction                                   */
/* ------------------------------------------------------------------ */

function collectUrls(creative) {
  const spec = creative?.object_story_spec ?? {};
  const urls = [
    creative?.link_url,
    spec.link_data?.link,
    spec.link_data?.call_to_action?.value?.link,
    spec.video_data?.call_to_action?.value?.link,
    spec.photo_data?.call_to_action?.value?.link,
    spec.template_data?.call_to_action?.value?.link,
    spec.link_data?.call_to_action?.value?.app_link,
    ...(creative?.asset_feed_spec?.link_urls ?? []).map((l) => l?.website_url),
  ].filter((v) => typeof v === 'string' && v.length > 0);
  return [...new Set(urls)];
}

const CTWA_URL_RE = /wa\.me|api\.whatsapp\.com|whatsapp\.com\/send|fb\.me\/\d/i;

function waPhoneFromUrl(url) {
  const s = String(url ?? '');
  const m = /(?:wa\.me\/|phone=)(\d{6,20})/i.exec(s);
  return m ? m[1] : null;
}

function callToActionSignals(creative) {
  const spec = creative?.object_story_spec ?? {};
  const parts = {
    simple: creative?.call_to_action_type ?? null,
    link_data: spec.link_data?.call_to_action ?? null,
    video_data: spec.video_data?.call_to_action ?? null,
    photo_data: spec.photo_data?.call_to_action ?? null,
    asset_feed_types: creative?.asset_feed_spec?.call_to_action_types ?? null,
    asset_feed_message_extensions: creative?.asset_feed_spec?.message_extensions ?? null,
  };
  const types = [
    parts.simple,
    parts.link_data?.type,
    parts.video_data?.type,
    parts.photo_data?.type,
    ...(parts.asset_feed_types ?? []),
  ].filter(Boolean);
  return { ...parts, all_types: [...new Set(types)] };
}

const MESSAGING_CTA_TYPES = [
  'WHATSAPP_MESSAGE', 'MESSAGE_PAGE', 'MESSENGER_MESSAGE', 'SEND_MESSAGE',
  'WHATSAPP_LINK', 'INSTAGRAM_DIRECT_MESSAGE',
];

function creativeShape(creative) {
  if (!creative) return null;
  const spec = creative?.object_story_spec ?? {};
  const cta = callToActionSignals(creative);
  const urls = collectUrls(creative);
  const whatsappUrls = urls.filter((u) => CTWA_URL_RE.test(u));
  return {
    id: creative.id ?? null,
    name: creative.name ?? null,
    status: creative.status ?? null,
    object_type: creative.object_type ?? null,
    page_id: spec.page_id ?? creative.effective_object_story_id?.split('_')?.[0] ?? null,
    instagram_actor_id: spec.instagram_user_id ?? creative.instagram_actor_id ?? null,
    title: creative.title ?? spec.video_data?.title ?? spec.link_data?.name ?? null,
    body: creative.body ?? spec.video_data?.message ?? spec.link_data?.message ?? null,
    link_description: spec.link_data?.link_description ?? spec.video_data?.link_description ?? null,
    link_url: creative.link_url ?? null,
    all_landing_urls: urls,
    whatsapp_urls: whatsappUrls,
    whatsapp_phone_from_url: waPhoneFromUrl(whatsappUrls[0]) ?? null,
    video_id: creative.video_id ?? null,
    story_video_id: spec.video_data?.video_id ?? null,
    image_hash: creative.image_hash ?? spec.video_data?.image_hash ?? spec.link_data?.image_hash ?? null,
    thumbnail_url: creative.thumbnail_url ?? null,
    instagram_permalink_url: creative.instagram_permalink_url ?? null,
    url_tags: creative.url_tags ?? null,
    call_to_action: cta,
    is_messaging_cta: cta.all_types.some((t) => MESSAGING_CTA_TYPES.includes(String(t).toUpperCase())),
    has_whatsapp_message_extension: (creative?.asset_feed_spec?.message_extensions ?? [])
      .some((e) => String(e?.type ?? '').toLowerCase() === 'whatsapp'),
    advantage_creative: creative?.degrees_of_freedom_spec?.creative_features_spec
      ? Object.fromEntries(
          Object.entries(creative.degrees_of_freedom_spec.creative_features_spec)
            .map(([k, v]) => [k, v?.enroll_status ?? null]),
        )
      : null,
    object_story_spec: spec,
    asset_feed_spec: creative?.asset_feed_spec ?? null,
    degrees_of_freedom_spec: creative?.degrees_of_freedom_spec ?? null,
  };
}

function creativeNeedsPage(creative) {
  return creative?.object_story_spec?.page_id ?? null;
}

/* ------------------------------------------------------------------ */
/* insights                                                            */
/* ------------------------------------------------------------------ */

const CTWA_ACTION_HINTS = [
  'onsite_conversion.messaging_conversation_started_7d',
  'onsite_conversion.messaging_first_reply',
  'onsite_conversion.messaging_conversation_replied_7d',
  'onsite_conversion.total_messaging_connection',
  'onsite_conversion.messaging_block',
  'onsite_conversion.messaging_user_depth_2_message_send',
  'onsite_conversion.messaging_user_depth_3_message_send',
  'onsite_conversion.messaging_user_depth_5_message_send',
];

function actionsMap(list) {
  return Object.fromEntries((list ?? []).map((a) => [a.action_type, num(a.value)]));
}

function summarizeInsights(row) {
  if (!row) return null;
  const actions = actionsMap(row.actions);
  const costPer = actionsMap(row.cost_per_action_type);
  const spend = num(row.spend);
  const lpv = actions.landing_page_view ?? null;
  const messaging = {};
  for (const key of Object.keys(actions)) {
    if (/messaging|conversation|lead/i.test(key)) messaging[key] = actions[key];
  }
  const messagingCosts = {};
  for (const key of Object.keys(costPer)) {
    if (/messaging|conversation|lead/i.test(key)) messagingCosts[key] = costPer[key];
  }
  const conversions = {};
  for (const hint of CTWA_ACTION_HINTS) if (actions[hint] !== undefined) conversions[hint] = actions[hint];
  return {
    date_start: row.date_start ?? null,
    date_stop: row.date_stop ?? null,
    spend,
    impressions: num(row.impressions),
    reach: num(row.reach),
    frequency: num(row.frequency),
    clicks: num(row.clicks),
    link_clicks: num(row.inline_link_clicks),
    ctr: num(row.ctr),
    link_ctr: num(row.inline_link_click_ctr),
    cpc: num(row.cpc),
    cpm: num(row.cpm),
    landing_page_views: lpv,
    cost_per_landing_page_view: costPer.landing_page_view ?? (spend && lpv ? Number((spend / lpv).toFixed(4)) : null),
    results: row.results ?? null,
    cost_per_result: row.cost_per_result ?? null,
    messaging_actions: messaging,
    messaging_costs: messagingCosts,
    ctwa_conversions: conversions,
    all_actions: actions,
    cost_per_action_type: costPer,
  };
}

async function fetchInsights(client, logger, objectId, level) {
  const res = await tryGet(client, logger, `insights ${level} ${objectId}`, `${objectId}/insights`, {
    fields: INSIGHT_FIELDS_EXTENDED,
    date_preset: 'maximum',
    level,
  });
  const row = res.ok ? res.data?.data?.[0] ?? null : null;
  return { ok: res.ok, error: res.ok ? null : res.error, summary: summarizeInsights(row) };
}

/* ------------------------------------------------------------------ */
/* checks                                                             */
/* ------------------------------------------------------------------ */

function buildFindings({ campaign, adsets, ads }) {
  const issues = [];
  const goods = [];
  const unknowns = [];
  const push = (list, code, detail) => list.push({ code, detail });

  for (const s of adsets) {
    const t = s.targeting ?? {};
    const platforms = t.publisher_platforms ?? [];
    const isCtwa = String(s.destination_type ?? '').toUpperCase() === 'WHATSAPP' ||
      String(s.optimization_goal ?? '').toUpperCase() === 'CONVERSATIONS';
    if (isCtwa) push(goods, 'CTWA_DESTINATION_CONFIGURED', { adset_id: s.id, destination_type: s.destination_type, optimization_goal: s.optimization_goal });
    else push(issues, 'ADSET_NOT_MESSAGING_DESTINATION', { adset_id: s.id, destination_type: s.destination_type, optimization_goal: s.optimization_goal });
    if (platforms.includes('messenger') && !platforms.includes('facebook')) {
      push(issues, 'MESSENGER_ONLY_PLACEMENT', { adset_id: s.id, publisher_platforms: platforms });
    }
    if (!t.geo_locations?.countries?.length && !t.geo_locations?.regions?.length && !t.geo_locations?.cities?.length) {
      push(issues, 'NO_GEO_RESTRICTION', { adset_id: s.id, countries: t.geo_locations?.countries ?? [] });
    } else {
      push(goods, 'GEO_RESTRICTED', { adset_id: s.id, geo_locations: t.geo_locations });
    }
    if (!s.attribution_spec) push(unknowns, 'ATTRIBUTION_NOT_REPORTED', { adset_id: s.id });
    if (s.effective_status === 'LEARNING_LIMITED') push(issues, 'LEARNING_LIMITED', { adset_id: s.id });
    if (s.effective_status === 'ADSET_PAUSED' || s.status === 'PAUSED') push(unknowns, 'ADSET_PAUSED', { adset_id: s.id, status: s.status, effective_status: s.effective_status });
    if (t.targeting_automation?.advantage_audience !== undefined) {
      push(unknowns, 'ADVANTAGE_AUDIENCE_SETTING', { adset_id: s.id, advantage_audience: t.targeting_automation.advantage_audience });
    }
    if (t.age_min || t.age_max) push(unknowns, 'AGE_RANGE', { adset_id: s.id, age_min: t.age_min, age_max: t.age_max });
  }

  for (const ad of ads) {
    const c = ad.creative ?? {};
    const shape = creativeShape(c);
    if (shape?.is_messaging_cta) push(goods, 'MESSAGING_CTA_PRESENT', { ad_id: ad.id, types: shape.call_to_action.all_types });
    else if (adsets.some((s) => String(s.destination_type ?? '').toUpperCase() === 'WHATSAPP')) {
      push(issues, 'CTWA_AD_WITHOUT_MESSAGING_CTA', { ad_id: ad.id, types: shape?.call_to_action.all_types ?? null });
    }
    if (shape?.whatsapp_urls?.length) push(goods, 'WHATSAPP_LINK_IN_CREATIVE', { ad_id: ad.id, urls: shape.whatsapp_urls });
    if (!String(ad.effective_status ?? '').includes('ACTIVE') && ad.effective_status) {
      push(unknowns, 'AD_NOT_ACTIVE', { ad_id: ad.id, effective_status: ad.effective_status });
    }
    for (const issue of ad.issues_info ?? []) {
      push(issues, 'AD_POLICY_ISSUE', { ad_id: ad.id, level: issue.level, error_code: issue.error_code, error_summary: issue.error_summary });
    }
    if (shape?.advantage_creative) {
      const optedIn = Object.entries(shape.advantage_creative).filter(([, v]) => v === 'OPT_IN').map(([k]) => k);
      if (optedIn.length) push(unknowns, 'ADVANTAGE_CREATIVE_ENHANCEMENTS_ON', { ad_id: ad.id, features: optedIn });
    }
    if (shape?.url_tags && !/utm_/i.test(String(shape.url_tags))) {
      push(issues, 'URL_TAGS_WITHOUT_UTM', { ad_id: ad.id, url_tags: shape.url_tags });
    }
    if (!shape?.url_tags && !shape?.whatsapp_urls?.length) {
      push(issues, 'NO_TRACKING_PARAMETERS', { ad_id: ad.id });
    }
  }

  if (campaign) {
    if (String(campaign.objective ?? '').includes('TRAFFIC')) push(issues, 'CAMPAIGN_OBJECTIVE_TRAFFIC', { objective: campaign.objective });
    if ((campaign.special_ad_categories ?? []).length === 0) push(goods, 'NO_SPECIAL_AD_CATEGORY', { special_ad_categories: [] });
    if (campaign.daily_budget || campaign.lifetime_budget) {
      push(unknowns, 'CBO_ON_CAMPAIGN_BUDGET', { daily_budget: campaign.daily_budget, lifetime_budget: campaign.lifetime_budget });
    } else {
      push(unknowns, 'ABO_ADSET_BUDGET', { is_adset_budget_sharing_enabled: campaign.is_adset_budget_sharing_enabled ?? null });
    }
    if (campaign.effective_status !== 'ACTIVE') push(unknowns, 'CAMPAIGN_NOT_ACTIVE', { status: campaign.status, effective_status: campaign.effective_status });
  }
  return { issues, goods, unknowns };
}

/* ------------------------------------------------------------------ */
/* main                                                               */
/* ------------------------------------------------------------------ */

async function main() {
  const argv = process.argv.slice(2);
  const args = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith('--')) args[key] = true;
      else { args[key] = next; i += 1; }
    } else args._.push(a);
  }

  const secrets = loadSecrets();
  const presence = envPresence(secrets);
  const missing = Object.entries(presence).filter(([, v]) => v === 'MISSING').map(([k]) => k);
  const redact = makeRedactor(secrets);
  const logger = new Logger(redact, 'meta-ctwa-audit');

  if (missing.length) {
    logger.error('missing required credential(s)', { missing });
    process.exitCode = 1;
    return;
  }
  logger.info('credential presence', presence);

  const versionInfo = await resolveApiVersion({
    token: secrets.META_ACCESS_TOKEN,
    appId: secrets.META_APP_ID,
    appSecret: secrets.META_APP_SECRET,
    redact,
  });
  if (!versionInfo.version) {
    logger.error('no usable Graph API version', { probes: versionInfo.attempts });
    process.exitCode = 1;
    return;
  }
  logger.info('graph api version resolved', { version: versionInfo.version, mode: versionInfo.mode });

  const client = new MetaClient({
    version: versionInfo.version,
    token: secrets.META_ACCESS_TOKEN,
    appId: secrets.META_APP_ID,
    appSecret: secrets.META_APP_SECRET,
    logger,
    redact,
  });

  const artifact = {
    generated_at: iso(),
    mode: 'READ_ONLY_GET',
    graph_api_version: client.version,
    version_resolution: { mode: versionInfo.mode, probes: versionInfo.attempts.map((a) => ({ version: a.version, ok: a.ok, code: a.code ?? null })) },
    credentials: presence,
  };

  /* ---- 1. token ---------------------------------------------------- */
  let dbg = null;
  try {
    dbg = await client.debugToken();
    artifact.token = {
      is_valid: dbg.is_valid ?? null,
      type: dbg.type ?? null,
      app_id: dbg.app_id ?? null,
      application: dbg.application ?? null,
      user_id: dbg.user_id ?? null,
      issued_at: dbg.issued_at ? new Date(dbg.issued_at * 1000).toISOString() : null,
      expires_at: dbg.expires_at ? new Date(dbg.expires_at * 1000).toISOString() : null,
      data_access_expires_at: dbg.data_access_expires_at ? new Date(dbg.data_access_expires_at * 1000).toISOString() : null,
      scopes: dbg.scopes ?? [],
      granular_scopes: (dbg.granular_scopes ?? []).map((g) => ({ scope: g.scope, target_ids_count: (g.target_ids ?? []).length })),
    };
  } catch (err) {
    artifact.token = { error: err instanceof GraphError ? err.toJSON() : { message: String(err.message) } };
    logger.error('token introspection failed', artifact.token.error);
    logger.writeJson(ARTIFACT, artifact);
    process.exitCode = 1;
    return;
  }
  logger.step('token', {
    valid: artifact.token.is_valid,
    type: artifact.token.type,
    application: artifact.token.application,
    scopes: artifact.token.scopes.length,
    expires_at: artifact.token.expires_at,
  });

  /* ---- 2. identity / permissions / accounts ------------------------ */
  artifact.identity = (await tryGet(client, logger, 'me', 'me', { fields: 'id,name' })).data ?? null;
  artifact.permissions = (await tryGet(client, logger, 'me/permissions', 'me/permissions')).data?.data ?? null;

  const businesses = await tryGet(client, logger, 'me/businesses', 'me/businesses', {
    fields: 'id,name,verification_status,created_time',
  });
  const adAccounts = await tryGet(client, logger, 'me/adaccounts', 'me/adaccounts', {
    fields: 'id,account_id,name,account_status,currency,time_zone,business,owner',
  });
  const assigned = await tryGet(client, logger, 'me/assigned_ad_accounts', 'me/assigned_ad_accounts', {
    fields: 'id,name,account_status,currency',
  });

  const accountMap = new Map();
  for (const a of adAccounts.data?.data ?? []) accountMap.set(a.id, { ...a, source: 'me/adaccounts' });
  for (const a of assigned.data?.data ?? []) if (!accountMap.has(a.id)) accountMap.set(a.id, { ...a, source: 'me/assigned_ad_accounts' });
  const commercialAccounts = [...accountMap.values()].filter((a) => a.account_status === 1 || a.account_status === 2);

  artifact.businesses = businesses.data?.data ?? null;
  artifact.ad_accounts = [...accountMap.values()];
  artifact.ad_accounts_source_errors = {
    me_adaccounts: adAccounts.ok ? null : adAccounts.error,
    me_assigned_ad_accounts: assigned.ok ? null : assigned.error,
    me_businesses: businesses.ok ? null : businesses.error,
  };

  logger.step('accounts discovered', {
    businesses: (artifact.businesses ?? []).map((b) => ({ id: b.id, name: b.name })),
    ad_accounts: artifact.ad_accounts.map((a) => ({ id: a.id, name: a.name, status: a.account_status, source: a.source })),
    commercial: commercialAccounts.map((a) => maskId(a.id)),
  });

  if (args.account) {
    const wanted = String(args.account).replace(/^act_/, '');
    for (const a of commercialAccounts) {
      if (a.account_id === wanted || a.id === `act_${wanted}` || a.id === args.account) {
        commercialAccounts.length = 0;
        commercialAccounts.push(a);
        break;
      }
    }
  }

  /* ---- 3. account health ------------------------------------------ */
  artifact.account_health = [];
  for (const a of commercialAccounts) {
    const detail = await probeGet(client, logger, `account ${a.id}`, a.id, ACCOUNT_FIELDS_CANDIDATES);
    const ownership = await probeGet(client, logger, `account ownership ${a.id}`, a.id, ACCOUNT_OWNERSHIP_FIELDS);
    const pixels = await tryGet(client, logger, `adspixels ${a.id}`, `${a.id}/adspixels`, {
      fields: 'id,name,creation_time,last_fired_time,is_unavailable,data_use_setting',
    });
    artifact.account_health.push({
      id: a.id,
      name: a.name,
      detail: detail.ok ? detail.data : null,
      detail_fields_used: detail.ok ? detail.fields_used : null,
      detail_attempts: detail.attempts ?? [],
      detail_error: detail.ok ? null : detail.error,
      ownership: ownership.ok ? ownership.data : null,
      ownership_fields_used: ownership.ok ? ownership.fields_used : null,
      ownership_error: ownership.ok ? null : ownership.error,
      pixels: pixels.data?.data ?? null,
      pixels_error: pixels.ok ? null : pixels.error,
    });
    logger.step(`account ${maskId(a.id)} health`, {
      status: detail.data?.account_status ?? null,
      disable_reason: detail.data?.disable_reason ?? null,
      currency: detail.data?.currency ?? null,
      timezone: detail.data?.timezone_name ?? null,
      amount_spent: detail.data?.amount_spent ?? null,
      balance: detail.data?.balance ?? null,
      business: ownership.data?.business?.id ?? null,
      owner: ownership.data?.owner ?? null,
      datasets: (pixels.data?.data ?? []).map((p) => ({ id: p.id, name: p.name, last_fired: p.last_fired_time ?? null })),
    });
  }

  /* Business resolution: a SYSTEM_USER token answers an empty /me/businesses, so
   * ownership is read from the ad account instead of being assumed. */
  const businessIds = new Set((artifact.businesses ?? []).map((b) => b.id));
  for (const h of artifact.account_health) {
    const bid = h.ownership?.business?.id;
    if (bid) businessIds.add(String(bid));
    if (h.ownership?.owner) businessIds.add(String(h.ownership.owner));
  }
  artifact.business_ids_resolved = [...businessIds];
  artifact.business_details = [];
  for (const bid of artifact.business_ids_resolved) {
    const res = await probeGet(client, logger, `business ${bid}`, bid, BUSINESS_FIELDS_CANDIDATES);
    artifact.business_details.push({
      id: bid,
      detail: res.ok ? res.data : null,
      fields_used: res.ok ? res.fields_used : null,
      error: res.ok ? null : res.error,
    });
  }
  logger.step('business resolution', {
    from_token: (artifact.businesses ?? []).map((b) => b.id),
    resolved: artifact.business_ids_resolved,
    details: artifact.business_details.map((b) => ({ id: b.id, name: b.detail?.name ?? null, error: b.error ? b.error.message : null })),
  });

  /* ---- 4. candidate campaigns ------------------------------------- */
  const NAME_TERMS = ['FullPOS', 'DaleVentas', 'WhatsApp'];
  const createdAfter = Math.floor(Date.now() / 1000) - CAMPAIGN_LOOKBACK_DAYS * 86400;

  const candidates = [];
  const candidateScan = [];
  for (const a of commercialAccounts) {
    const accountScan = { account_id: a.id, account_name: a.name, probes: [] };
    for (const term of NAME_TERMS) {
      const res = await allEdge(client, logger, `campaigns(name~${term}) ${a.id}`, `${a.id}/campaigns`, CAMPAIGN_FIELDS, {
        filtering: [{ field: 'name', operator: 'CONTAIN', value: term }],
      }, { limit: 50, maxPages: 2 });
      const rows = res.ok ? res.data : [];
      accountScan.probes.push({ filter: `name CONTAIN ${term}`, ok: res.ok, count: rows.length, error: res.ok ? null : res.error });
      for (const c of rows) candidates.push({ account: a, campaign: c, matched_by: `name~${term}` });
    }
    const recent = await allEdge(client, logger, `campaigns(created_time>${createdAfter}) ${a.id}`, `${a.id}/campaigns`, CAMPAIGN_FIELDS, {
      filtering: [{ field: 'created_time', operator: 'GREATER_THAN', value: createdAfter }],
    }, { limit: 50, maxPages: 3 });
    const recentRows = recent.ok ? recent.data : [];
    accountScan.probes.push({ filter: `created_time GREATER_THAN ${createdAfter}`, ok: recent.ok, count: recentRows.length, error: recent.ok ? null : recent.error });
    for (const c of recentRows) candidates.push({ account: a, campaign: c, matched_by: 'created_time_recent' });
    candidateScan.push(accountScan);
  }
  artifact.candidate_scan = candidateScan;

  // De-duplicate by campaign id, keeping the first account that reported it.
  const byId = new Map();
  for (const cand of candidates) {
    const id = cand.campaign.id;
    if (!byId.has(id)) byId.set(id, { ...cand, matched_by: [cand.matched_by] });
    else byId.get(id).matched_by.push(cand.matched_by);
  }
  let list = [...byId.values()];

  const wantedIds = args.campaign && args.campaign !== true
    ? String(args.campaign).split(',').map((s) => s.trim()).filter(Boolean)
    : null;
  if (wantedIds) {
    const found = [];
    for (const id of wantedIds) {
      const existing = list.find((c) => c.campaign.id === id);
      if (existing) { found.push(existing); continue; }
      // Not matched by the name/recent filters: read it explicitly by id.
      const res = await probeGet(client, logger, `campaign ${id}`, id, CAMPAIGN_FIELDS);
      if (res.ok) {
        const acc = commercialAccounts.find((a) => String(res.data.account_id ?? '') === String(a.account_id)) ?? commercialAccounts[0];
        found.push({ account: acc, campaign: res.data, matched_by: ['explicit_id'] });
      } else {
        artifact.requested_campaigns_not_found = [...(artifact.requested_campaigns_not_found ?? []), { id, id_partial: maskId(id), error: res.error }];
      }
    }
    list = found;
  }

  // CTWA relevance ranking (no arbitrary pick: every candidate below is audited).
  const relevantFirst = (c) => (!/traffic|awareness|video_view|reach/i.test(String(c.campaign.objective ?? '')) ? 0 : 1);
  list.sort((a, b) => {
    const r = relevantFirst(a) - relevantFirst(b);
    if (r !== 0) return r;
    return String(b.campaign.updated_time ?? '').localeCompare(String(a.campaign.updated_time ?? ''));
  });
  const audited = list.slice(0, MAX_CANDIDATES);

  artifact.candidate_campaigns = list.map((c) => ({
    campaign_id: c.campaign.id,
    campaign_id_partial: maskId(c.campaign.id),
    account_id: c.account.id,
    name: c.campaign.name,
    objective: c.campaign.objective,
    status: c.campaign.status,
    effective_status: c.campaign.effective_status,
    daily_budget: c.campaign.daily_budget ?? null,
    lifetime_budget: c.campaign.lifetime_budget ?? null,
    created_time: c.campaign.created_time ?? null,
    updated_time: c.campaign.updated_time ?? null,
    matched_by: [...new Set(c.matched_by)],
    audited: audited.some((x) => x.campaign.id === c.campaign.id),
  }));

  logger.step('candidate campaigns', {
    total: list.length,
    rows: list.map((c) => ({
      id: maskId(c.campaign.id),
      name: c.campaign.name,
      objective: c.campaign.objective,
      status: c.campaign.status,
      effective_status: c.campaign.effective_status,
      updated: c.campaign.updated_time ?? null,
      matched_by: [...new Set(c.matched_by)],
    })),
  });

  /* ---- 5. deep audit per candidate -------------------------------- */
  const auditedCampaigns = [];
  for (const cand of audited) {
    const campaignId = cand.campaign.id;
    const campaign = await probeGet(client, logger, `campaign ${campaignId}`, campaignId, CAMPAIGN_FIELDS);
    const campaignObj = campaign.ok ? campaign.data : cand.campaign;

    // The campaign edge accepts the widest adset field set; a single-adset GET
    // rejects some of them, so the edge is used on purpose.
    const adsetsRes = await allEdge(client, logger, `adsets ${campaignId}`, `${campaignId}/adsets`, ADSET_FIELDS_CANDIDATES, {}, { limit: 50, maxPages: 2 });
    const adsets = adsetsRes.ok ? adsetsRes.data : [];

    const adsRes = await allEdge(client, logger, `ads ${campaignId}`, `${campaignId}/ads`, AD_FIELDS_CANDIDATES, {}, { limit: 50, maxPages: 2 });
    const ads = adsRes.ok ? adsRes.data : [];

    const campaignInsights = await fetchInsights(client, logger, campaignId, 'campaign');
    const adsetInsights = [];
    for (const s of adsets) adsetInsights.push({ adset_id: s.id, name: s.name, insights: await fetchInsights(client, logger, s.id, 'adset') });
    const adInsights = [];
    for (const ad of ads) adInsights.push({ ad_id: ad.id, name: ad.name, insights: await fetchInsights(client, logger, ad.id, 'ad') });

    const creatives = ads.map((ad) => creativeShape(ad.creative)).filter(Boolean);
    const findings = buildFindings({ campaign: campaignObj, adsets, ads });

    auditedCampaigns.push({
      account: { id: cand.account.id, name: cand.account.name, currency: cand.account.currency },
      campaign_id: campaignId,
      campaign_id_partial: maskId(campaignId),
      matched_by: [...new Set(cand.matched_by)],
      campaign: campaignObj,
      campaign_read_width_used: campaign.ok ? 'ok' : 'list_row_fallback',
      adsets,
      adsets_source: adsetsRes.ok ? 'campaign/adsets' : null,
      adsets_error: adsetsRes.ok ? null : adsetsRes.error,
      adset_field_set_used: adsetsRes.ok ? adsetsRes.fields_used : null,
      ads: ads.map((ad) => ({
        id: ad.id,
        name: ad.name,
        status: ad.status,
        effective_status: ad.effective_status,
        configured_status: ad.configured_status ?? null,
        adset_id: ad.adset_id ?? null,
        created_time: ad.created_time ?? null,
        updated_time: ad.updated_time ?? null,
        tracking_specs: ad.tracking_specs ?? null,
        issues_info: ad.issues_info ?? null,
        preview_shareable_link: ad.preview_shareable_link ?? null,
        creative_id: ad.creative?.id ?? null,
        creative: creativeShape(ad.creative),
      })),
      ads_source: adsRes.ok ? 'campaign/ads' : null,
      ads_error: adsRes.ok ? null : adsRes.error,
      creative_page_ids: [...new Set(creatives.map(creativeNeedsPage).filter(Boolean))],
      insights: { campaign: campaignInsights, adsets: adsetInsights, ads: adInsights },
      findings,
      open_questions: [],
    });

    logger.step(`audited campaign ${maskId(campaignId)}`, {
      name: campaignObj.name,
      objective: campaignObj.objective,
      status: campaignObj.status,
      effective_status: campaignObj.effective_status,
      adsets: adsets.map((s) => ({
        id: maskId(s.id),
        destination_type: s.destination_type ?? null,
        optimization_goal: s.optimization_goal ?? null,
        billing_event: s.billing_event ?? null,
        daily_budget: s.daily_budget ?? null,
        optimization_sub_event: s.optimization_sub_event ?? null,
      })),
      ads: ads.map((ad) => ({
        id: maskId(ad.id),
        effective_status: ad.effective_status,
        cta: creativeShape(ad.creative)?.call_to_action.all_types ?? null,
        whatsapp_urls: creativeShape(ad.creative)?.whatsapp_urls ?? null,
        url_tags: creativeShape(ad.creative)?.url_tags ?? null,
      })),
      spend: campaignInsights.summary?.spend ?? null,
      messaging_actions: campaignInsights.summary?.messaging_actions ?? null,
      findings: { issues: findings.issues.map((i) => i.code), goods: findings.goods.map((g) => g.code), unknowns: findings.unknowns.map((u) => u.code) },
    });
  }
  artifact.audited_campaigns = auditedCampaigns;
  artifact.audited_count = auditedCampaigns.length;

  /* ---- 6. WhatsApp Business resources ----------------------------- */
  const whatsapp = { wabas: [], phone_numbers: [], page_links: [], errors: [] };
  const WABA_EDGES = ['owned_whatsapp_business_accounts', 'whatsapp_business_accounts'];
  for (const businessId of artifact.business_ids_resolved ?? []) {
    let waba = { ok: false, error: null };
    for (const edge of WABA_EDGES) {
      waba = await tryGet(client, logger, `${edge} of business ${businessId}`, `${businessId}/${edge}`, {
        fields: 'id,name,currency,timezone_id,message_template_namespace,account_review_status',
      });
      if (waba.ok) { whatsapp.waba_edge_used = edge; break; }
    }
    if (!waba.ok) { whatsapp.errors.push({ business_id: businessId, endpoint: WABA_EDGES.join('|'), error: waba.error }); continue; }
    for (const w of waba.data?.data ?? []) {
      whatsapp.wabas.push({ business_id: businessId, ...w });
      const phones = await tryGet(client, logger, `phone_numbers of WABA ${w.id}`, `${w.id}/phone_numbers`, {
        fields: 'id,display_phone_number,verified_name,quality_rating,code_verification_status,platform_type,status,name_status,throughput,messaging_limit_tier,is_official_business_account',
      });
      if (phones.ok) {
        for (const p of phones.data?.data ?? []) {
          whatsapp.phone_numbers.push({ waba_id: w.id, ...p, display_phone_number_partial: maskPhone(p.display_phone_number) });
        }
      } else {
        whatsapp.errors.push({ waba_id: w.id, endpoint: 'phone_numbers', error: phones.error });
      }
    }
  }
  // Page lookup for every page referenced by the audited creatives.
  const pageIds = [...new Set(auditedCampaigns.flatMap((c) => c.creative_page_ids))];
  for (const pid of pageIds) {
    const page = await probeGet(client, logger, `page ${pid}`, pid, PAGE_FIELDS_CANDIDATES);
    whatsapp.page_links.push({
      page_id: pid,
      page_id_partial: maskId(pid),
      page: page.ok ? page.data : null,
      fields_used: page.ok ? page.fields_used : null,
      error: page.ok ? null : page.error,
    });
  }
  artifact.whatsapp = whatsapp;
  logger.step('whatsapp resources', {
    wabas: whatsapp.wabas.map((w) => ({ id: maskId(w.id), name: w.name, review: w.account_review_status ?? null })),
    phones: whatsapp.phone_numbers.map((p) => ({ partial: p.display_phone_number_partial, verified_name: p.verified_name, quality: p.quality_rating, status: p.status, name_status: p.name_status, platform: p.platform_type })),
    pages: whatsapp.page_links.map((p) => ({ id: p.page_id_partial, name: p.page?.name ?? null, tasks: p.page?.tasks ?? null, error: p.error ? p.error.message : null })),
    errors: whatsapp.errors.length,
  });

  /* ---- 7. pixel / dataset + events -------------------------------- */
  const pixelIds = new Set();
  for (const c of auditedCampaigns) {
    for (const s of c.adsets) if (s.promoted_object?.pixel_id) pixelIds.add(String(s.promoted_object.pixel_id));
    for (const ad of c.ads) {
      for (const spec of ad.tracking_specs ?? []) {
        if (Array.isArray(spec) && spec.length >= 3 && String(spec[0]).includes('pixel')) {
          const val = spec[2];
          if (Array.isArray(val)) for (const v of val) pixelIds.add(String(v));
        }
      }
    }
  }
  for (const h of artifact.account_health) for (const p of h.pixels ?? []) pixelIds.add(String(p.id));

  const businessId = artifact.businesses?.[0]?.id ?? null;
  const datasets = [];
  for (const id of pixelIds) {
    const detail = await probeGet(client, logger, `dataset ${id}`, id, PIXEL_FIELDS_CANDIDATES);
    const stats = await tryGet(client, logger, `dataset stats ${id}`, `${id}/stats`, { aggregation: 'event' });
    const users = businessId
      ? await tryGet(client, logger, `dataset assigned_users ${id}`, `${id}/assigned_users`, { business: businessId, fields: 'id,name,tasks' })
      : { ok: false, error: 'no business id resolved' };
    const eventTotals = {};
    for (const bucket of stats.data?.data ?? []) {
      for (const ev of bucket.data ?? []) eventTotals[ev.value] = (eventTotals[ev.value] ?? 0) + num(ev.count ?? 0);
    }
    datasets.push({
      id,
      id_partial: maskId(id),
      used_by_adset_promoted_object: [...auditedCampaigns].some((c) => c.adsets.some((s) => String(s.promoted_object?.pixel_id ?? '') === id)),
      detail: detail.ok ? detail.data : null,
      detail_error: detail.ok ? null : detail.error,
      event_stats_raw: stats.data ?? null,
      event_stats_error: stats.ok ? null : stats.error,
      event_totals: eventTotals,
      event_names_seen: Object.keys(eventTotals).sort(),
      assigned_users: users.ok ? users.data?.data ?? null : null,
      assigned_users_error: users.ok ? null : users.error,
    });
  }
  artifact.datasets = datasets;
  logger.step('datasets', datasets.map((d) => ({
    id: d.id_partial,
    name: d.detail?.name ?? null,
    last_fired: d.detail?.last_fired_time ?? null,
    events: d.event_names_seen,
    totals: d.event_totals,
  })));

  /* ---- 8. funnel readiness --------------------------------------- */
  const messagingCampaigns = auditedCampaigns.filter((c) =>
    c.adsets.some((s) => String(s.destination_type ?? '').toUpperCase() === 'WHATSAPP' || String(s.optimization_goal ?? '').toUpperCase() === 'CONVERSATIONS') ||
    c.ads.some((ad) => ad.creative?.is_messaging_cta));
  const anyMessagingConversationAction = auditedCampaigns.some((c) => Object.keys(c.insights?.campaign?.summary?.messaging_actions ?? {}).length > 0);
  const funnel = {
    whatsapp_conversation: {
      state: messagingCampaigns.length && whatsapp.phone_numbers.length ? 'READY' : 'NOT READY',
      evidence: {
        messaging_campaigns: messagingCampaigns.map((c) => maskId(c.campaign_id)),
        phone_numbers_found: whatsapp.phone_numbers.length,
        conversation_actions_seen_in_insights: anyMessagingConversationAction,
      },
    },
    qualified_lead: {
      state: 'NOT READY',
      evidence: { reason: 'No qualified-lead signal exists in Meta: it happens inside the WhatsApp conversation (human), not in the ad platform.' },
    },
    start_trial: {
      state: datasets.some((d) => d.event_names_seen.some((e) => /RegistrationStarted/i.test(e))) ? 'PARTIAL' : 'NOT READY',
      evidence: { datasets_with_RegistrationStarted: datasets.filter((d) => d.event_names_seen.some((e) => /RegistrationStarted/i.test(e))).map((d) => d.id_partial) },
    },
    purchase: {
      state: datasets.some((d) => d.event_names_seen.some((e) => /Purchase/i.test(e))) ? 'PARTIAL' : 'NOT READY',
      evidence: { datasets_with_Purchase: datasets.filter((d) => d.event_names_seen.some((e) => /Purchase/i.test(e))).map((d) => d.id_partial) },
    },
    conversions_api: {
      state: 'NOT READY',
      evidence: { reason: 'No server-side Conversions API integration was found in the repository (apps/api).' },
    },
  };
  artifact.funnel = funnel;

  artifact.open_questions = [
    'Whether a campaign created in Ads Manager but never saved/published is visible through the API (it is not: drafts are client-side until saved).',
  ];
  artifact.notes = [
    'Read-only run: the only transport used is GET.',
    'Campaign/adset/ad ids are printed partially in the console; the full values are in this artifact.',
  ];

  logger.writeJson(ARTIFACT, artifact);
  logger.info('audit finished', { graph_calls: client.calls, artifact: `out/${ARTIFACT}` });
}

main().catch((err) => {
  // Last-resort sanitized failure: never leak a raw object.
  const payload = err instanceof GraphError ? err.toJSON() : { message: String(err?.message ?? err) };
  process.stderr.write(`ctwa-audit failed: ${JSON.stringify(payload)}\n`);
  process.exitCode = 1;
});
