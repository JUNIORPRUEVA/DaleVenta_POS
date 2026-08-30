(function () {
  var defaults = {
    supportEmail: "ventas@fulltechrd.com",
    supportPhone: "829-531-9442",
    supportWhatsapp: "18295319442",
    supportHours: "Lunes a viernes de 9:00 a.m. a 6:00 p.m. AST"
  };

  function configValue(key) {
    var cfg = window.FULLPOS_PUBLIC_CONFIG || {};
    return (cfg[key] || defaults[key] || "").toString().trim();
  }

  function setText(selector, value) {
    document.querySelectorAll(selector).forEach(function (node) {
      node.textContent = value;
    });
  }

  function setHref(selector, href) {
    document.querySelectorAll(selector).forEach(function (node) {
      node.setAttribute("href", href);
    });
  }

  var email = configValue("supportEmail");
  var phone = configValue("supportPhone");
  var whatsapp = configValue("supportWhatsapp").replace(/[^0-9]/g, "");
  var hours = configValue("supportHours");

  setText("[data-support-email]", email);
  setText("[data-support-phone]", phone);
  setText("[data-support-hours]", hours);
  setHref("[data-support-mailto]", "mailto:" + email + "?subject=Soporte%20FullPOS%20Cloud");
  setHref("[data-support-whatsapp]", "https://wa.me/" + whatsapp + "?text=Hola%2C%20necesito%20ayuda%20con%20FullPOS%20Cloud");
})();
