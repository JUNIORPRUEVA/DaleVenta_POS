/* Verificacion de integridad en la base LOCAL tras el registro.
   Uso: node qa-fase3-dbcheck.js <email> */
const { PrismaClient } = require('@prisma/client');
const p = new PrismaClient();

(async () => {
  const email = (process.argv[2] || '').trim();
  if (!email) throw new Error('falta el email');

  const u = await p.user.findUnique({
    where: { email },
    select: {
      id: true,
      role: true,
      telefono: true,
      companyId: true,
      company: {
        select: {
          id: true,
          name: true,
          licenseStatus: true,
          trialStartedAt: true,
          trialEndsAt: true,
          maxUsers: true,
          maxProducts: true,
          onboardingRequired: true,
          onboardingStatus: true,
        },
      },
    },
  });
  if (!u) throw new Error('usuario no encontrado');

  const cfg = await p.appConfig.findMany({
    where: { companyId: u.companyId },
    select: {
      id: true,
      companyName: true,
      businessType: true,
      businessAgeRange: true,
      businessSize: true,
      welcomeCompletedAt: true,
    },
  });

  const members = await p.companyMember.findMany({
    where: { companyId: u.companyId },
    select: { role: true, status: true, userId: true },
  });

  const tickets = await p.sessionHandoffTicket.count({ where: { userId: u.id } });
  const usedTickets = await p.sessionHandoffTicket.count({
    where: { userId: u.id, usedAt: { not: null } },
  });
  const sessions = await p.authSession.count({ where: { userId: u.id } });
  const activeSessions = await p.authSession.count({
    where: { userId: u.id, revokedAt: null },
  });
  const sameName = await p.company.count({ where: { name: u.company.name } });
  const usersWithEmail = await p.user.count({ where: { email } });

  const dias = Math.round(
    (new Date(u.company.trialEndsAt) - new Date(u.company.trialStartedAt)) / 86400000,
  );

  console.log(
    JSON.stringify(
      {
        usuario: { role: u.role, telefono: u.telefono, conEseEmail: usersWithEmail },
        empresa: {
          nombre: u.company.name,
          licenseStatus: u.company.licenseStatus,
          maxUsers: u.company.maxUsers,
          maxProducts: u.company.maxProducts,
          onboardingRequired: u.company.onboardingRequired,
          onboardingStatus: u.company.onboardingStatus,
          empresasConEseNombre: sameName,
        },
        trialDias: dias,
        miembros: members,
        appConfigFilas: cfg.length,
        appConfig: cfg,
        tickets,
        ticketsUsados: usedTickets,
        sesiones: sessions,
        sesionesActivas: activeSessions,
      },
      null,
      1,
    ),
  );

  await p.$disconnect();
})().catch(async (e) => {
  console.error('ERROR:', e.message);
  await p.$disconnect();
  process.exit(1);
});
