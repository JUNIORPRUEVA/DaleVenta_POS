import { FulltechStore as fallbackStore } from "./data.js";

(async function () {
  const companyOverride = {
    phone: "+1 829 477 0756",
    whatsapp: "18294770756",
    address: "Calle Beller #9, Higuey, La Altagracia, Republica Dominicana"
  };
  let store = fallbackStore;
  let storeSource = "fallback";
  const state = {
    category: "Todos",
    query: "",
    sort: "featured"
  };
  const defaultApiBase = "https://fulltech-tienda-fulltechapppwa.gcdndd.easypanel.host";

  try {
    const apiBase = (window.FULLTECH_API_BASE_URL || defaultApiBase).replace(/\/$/, "");
    const response = await fetch(`${apiBase}/website/public`, {
      headers: { Accept: "application/json" }
    });
    if (response.ok) {
      const payload = await response.json();
      if (Array.isArray(payload.products) && payload.products.length > 0) {
        const apiProducts = payload.products.map((product) => ({
          id: String(product.id),
          name: product.name,
          category: product.category || "Sin categoria",
          price: Number(product.price || 0),
          warranty: product.warranty || "Garantia segun producto",
          stock: product.stock == null ? null : Number(product.stock),
          image: product.image || "assets/logo.png",
          extraImages: Array.isArray(product.extraImages) ? product.extraImages : [],
          description: product.description || "Producto disponible en FULLTECH.",
          code: product.code || null,
          badge: product.stock == null ? "Consultar" : Number(product.stock) > 0 ? "Disponible" : "Bajo pedido",
          featured: product.featured === true
        }));
        store = {
          ...fallbackStore,
          company: {
            ...fallbackStore.company,
            ...(payload.company || {}),
            ...companyOverride,
            updatedAt: fallbackStore.company.updatedAt
          },
          categories: payload.categories || [...new Set(apiProducts.map((item) => item.category))],
          products: apiProducts,
          updatedAt: payload.updatedAt || fallbackStore.updatedAt
        };
        storeSource = "api";
      }
    }
  } catch (_) {
    store = fallbackStore;
  }
  store = {
    ...store,
    company: {
      ...store.company,
      ...companyOverride
    }
  };

  const money = new Intl.NumberFormat("es-DO", {
    style: "currency",
    currency: "DOP",
    maximumFractionDigits: 0
  });
  const imageFallback = "assets/tech-products.jpg";

  function escapeHtml(value) {
    return String(value ?? "").replace(/[&<>"']/g, (char) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#039;"
    })[char]);
  }

  function cart() {
    try {
      return JSON.parse(localStorage.getItem("fulltech-cart") || "{}");
    } catch (_) {
      return {};
    }
  }

  function saveCart(value) {
    localStorage.setItem("fulltech-cart", JSON.stringify(value));
    updateCartCount();
    renderCartSummary();
  }

  function cartItems() {
    return Object.values(cart());
  }

  function cartTotal() {
    return cartItems().reduce((sum, item) => sum + Number(item.price || 0) * Number(item.qty || 0), 0);
  }

  function updateCartCount() {
    const count = cartItems().reduce((sum, item) => sum + Number(item.qty || 0), 0);
    document.querySelectorAll("[data-cart-count]").forEach((node) => {
      node.textContent = String(count);
    });
  }

  function addToCart(productId) {
    const product = store.products.find((item) => item.id === productId);
    if (!product) return;
    const current = cart();
    current[productId] = {
      id: product.id,
      name: product.name,
      price: product.price,
      qty: (current[productId]?.qty || 0) + 1
    };
    saveCart(current);
    renderCart();
    const button = document.querySelector(`[data-add-to-cart="${CSS.escape(productId)}"]`);
    if (button) {
      const previous = button.innerHTML;
      button.textContent = "Agregado";
      button.classList.add("is-success");
      setTimeout(() => {
        button.innerHTML = previous || "Agregar";
        button.classList.remove("is-success");
      }, 900);
    }
  }

  function filteredProducts() {
    const query = state.query.trim().toLowerCase();
    let products = [...store.products];
    if (state.category !== "Todos") {
      products = products.filter((item) => item.category === state.category);
    }
    if (query) {
      products = products.filter((item) => {
        const haystack = `${item.name} ${item.category} ${item.description} ${item.badge || ""}`.toLowerCase();
        return haystack.includes(query);
      });
    }
    if (state.sort === "price-asc") products.sort((a, b) => a.price - b.price);
    if (state.sort === "price-desc") products.sort((a, b) => b.price - a.price);
    if (state.sort === "name") products.sort((a, b) => a.name.localeCompare(b.name));
    if (state.sort === "featured") products.sort((a, b) => Number(Boolean(b.featured)) - Number(Boolean(a.featured)));
    return products;
  }

  function productCard(product, mode = "button") {
    const action = mode === "link"
      ? '<a class="button" href="tienda.html">Ver tienda</a>'
      : `<button class="button" type="button" data-add-to-cart="${escapeHtml(product.id)}">Agregar</button>`;
    return `
      <article class="product-card">
        <div class="product-card__media">
          <button class="product-image-button" type="button" data-image-preview="${escapeHtml(product.image)}" data-image-title="${escapeHtml(product.name)}" aria-label="Ver foto de ${escapeHtml(product.name)}">
            <img class="product-card__image" src="${escapeHtml(product.image)}" alt="${escapeHtml(product.name)}" loading="lazy" onerror="this.onerror=null;this.src='${imageFallback}'">
          </button>
          ${product.badge ? `<span class="badge">${escapeHtml(product.badge)}</span>` : ""}
        </div>
        <div class="product-card__body">
          <div class="product-card__meta">
            <span>${escapeHtml(product.category)}</span>
            <span>${product.stock == null ? "Consultar stock" : `${escapeHtml(product.stock)} disp.`}</span>
          </div>
          <h3>${escapeHtml(product.name)}</h3>
          ${product.code ? `<span class="sku">Codigo: ${escapeHtml(product.code)}</span>` : ""}
          <p>${escapeHtml(product.description)}</p>
          <div class="product-card__footer">
            <div>
              <span class="microcopy">Desde</span>
              <div class="price">${money.format(product.price)}</div>
            </div>
            <div class="product-actions">
              ${action}
              <a class="button button--ghost" href="${buildProductWhatsApp(product)}">Consultar</a>
            </div>
          </div>
        </div>
      </article>
    `;
  }

  function shortText(value, max = 74) {
    const text = String(value || "").trim();
    return text.length > max ? `${text.slice(0, max - 1).trim()}...` : text;
  }

  function shortCategory(value) {
    return String(value || "Categoria").trim().split(/\s+/)[0] || "Categoria";
  }

  function storeCartIcon() {
    return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 18.5a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0Zm12 0a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0ZM6.1 6l1.1 6.2h8.9L17.4 8H8.2l-.3-2H5V4.4h4.2l.3 2h10.1l-2.1 7.4H6L4.6 6H2.8V4.4h2.8L6.1 6Z"/></svg>';
  }

  function storeProductCard(product) {
    const status = product.stock == null || Number(product.stock) > 0 ? "Disponible" : "Bajo pedido";
    return `
      <article class="store-product-card">
        <div class="store-product-media">
          <button class="store-product-image-button" type="button" data-image-preview="${escapeHtml(product.image)}" data-image-title="${escapeHtml(product.name)}" aria-label="Ver foto de ${escapeHtml(product.name)}">
            <img src="${escapeHtml(product.image)}" alt="${escapeHtml(product.name)}" loading="lazy" onerror="this.onerror=null;this.src='${imageFallback}'">
          </button>
          <span class="store-badge store-badge--ok">${escapeHtml(status)}</span>
          ${product.featured || product.badge ? '<span class="store-badge store-badge--deal">Oferta</span>' : ""}
          <button class="store-cart-add" type="button" data-add-to-cart="${escapeHtml(product.id)}" aria-label="Agregar ${escapeHtml(product.name)} al carrito">${storeCartIcon()}</button>
        </div>
        <div class="store-product-body">
          <h3>${escapeHtml(product.name)}</h3>
          <p>${escapeHtml(shortText(product.description))}</p>
          <strong>${money.format(product.price)}</strong>
        </div>
      </article>
    `;
  }

  function categoryImage(category) {
    return store.products.find((item) => item.category === category)?.image || store.products[0]?.image || "assets/logo.png";
  }

  function renderStoreSlider() {
    const target = document.querySelector("[data-store-slider]");
    if (!target) return;
    const slides = (store.products.filter((product) => product.featured).length
      ? store.products.filter((product) => product.featured)
      : store.products).slice(0, 4);
    target.innerHTML = `
      <div class="store-slides">
        ${slides.map((product, index) => `
          <article class="store-slide ${index === 0 ? "is-active" : ""}" data-store-slide>
            <img src="${escapeHtml(product.image)}" alt="${escapeHtml(product.name)}" onerror="this.onerror=null;this.src='${imageFallback}'">
            <div>
              <span>${escapeHtml(product.category)}</span>
              <h1>${escapeHtml(product.name)}</h1>
              <p>${escapeHtml(shortText(product.description, 88))}</p>
              <strong>${money.format(product.price)}</strong>
              <button class="store-offer-button" type="button" data-add-to-cart="${escapeHtml(product.id)}">Ver oferta</button>
            </div>
          </article>
        `).join("")}
      </div>
      <div class="store-dots">
        ${slides.map((_, index) => `<button class="${index === 0 ? "is-active" : ""}" type="button" data-store-dot="${index}" aria-label="Ver oferta ${index + 1}"></button>`).join("")}
      </div>
    `;
    let active = 0;
    const show = (index) => {
      const slideNodes = target.querySelectorAll("[data-store-slide]");
      const dots = target.querySelectorAll("[data-store-dot]");
      active = (index + slideNodes.length) % slideNodes.length;
      slideNodes.forEach((node, itemIndex) => node.classList.toggle("is-active", itemIndex === active));
      dots.forEach((node, itemIndex) => node.classList.toggle("is-active", itemIndex === active));
    };
    target.querySelectorAll("[data-store-dot]").forEach((dot) => {
      dot.addEventListener("click", () => show(Number(dot.dataset.storeDot || 0)));
    });
    if (slides.length > 1) setInterval(() => show(active + 1), 4500);
  }

  function renderStoreOffers() {
    const target = document.querySelector("[data-store-offers]");
    if (!target) return;
    const offers = store.products.filter((product) => product.featured || product.badge).slice(0, 8);
    target.innerHTML = (offers.length ? offers : store.products.slice(0, 8)).map(storeProductCard).join("");
  }

  function renderStoreCategories() {
    const target = document.querySelector("[data-store-categories]");
    if (!target) return;
    target.innerHTML = store.categories.map((category) => {
      const total = store.products.filter((item) => item.category === category).length;
      return `
        <a class="store-category-card" href="tienda.html?categoria=${encodeURIComponent(category)}">
          <img src="${escapeHtml(categoryImage(category))}" alt="${escapeHtml(category)}" onerror="this.onerror=null;this.src='${imageFallback}'">
          <strong>${escapeHtml(shortCategory(category))}</strong>
          <span>${total} producto${total === 1 ? "" : "s"}</span>
        </a>
      `;
    }).join("");
  }

  function renderStoreSections() {
    const target = document.querySelector("[data-store-sections]");
    if (!target) return;
    const products = filteredProducts();
    if (!products.length) {
      target.innerHTML = `
        <div class="empty-state">
          <h3>No encontramos productos</h3>
          <p>Prueba otra busqueda o escribenos por WhatsApp para cotizar lo que necesitas.</p>
          <a class="button button--accent" data-whatsapp-link>Consultar por WhatsApp</a>
        </div>
      `;
      fillCompanyData();
      return;
    }
    const categories = state.category === "Todos"
      ? store.categories.filter((category) => products.some((item) => item.category === category))
      : [state.category];
    target.innerHTML = categories.map((category) => {
      const categoryProducts = products.filter((item) => item.category === category);
      return `
        <section class="store-category-section">
          <div class="store-section-head"><h2>${escapeHtml(category)}</h2><a href="tienda.html?categoria=${encodeURIComponent(category)}">Ver todo</a></div>
          <div class="store-rail">${categoryProducts.map(storeProductCard).join("")}</div>
        </section>
      `;
    }).join("");
  }

  function renderProducts() {
    const target = document.querySelector("[data-products]");
    if (!target) return;
    const products = filteredProducts();
    const countTarget = document.querySelector("[data-product-count]");
    if (countTarget) countTarget.textContent = `${products.length} producto${products.length === 1 ? "" : "s"}`;
    const sourceTarget = document.querySelector("[data-store-source]");
    if (sourceTarget) {
      sourceTarget.textContent = storeSource === "api"
        ? "Productos sincronizados desde el punto de venta FULLTECH."
        : "Modo demostracion: configura FULLTECH_API_BASE_URL para usar productos reales del punto de venta.";
    }
    if (document.querySelector(".store-app")) {
      target.innerHTML = "";
      renderStoreSections();
      return;
    }
    if (!products.length) {
      target.innerHTML = `
        <div class="empty-state">
          <h3>No encontramos productos con esos filtros</h3>
          <p>Prueba otra categoria o escribenos por WhatsApp para buscar una solucion a medida.</p>
          <a class="button button--accent" data-whatsapp-link>Consultar disponibilidad</a>
        </div>
      `;
      fillCompanyData();
      return;
    }
    target.innerHTML = products.map((product) => productCard(product)).join("");
  }

  function renderFilters() {
    const target = document.querySelector("[data-filters]");
    if (!target) return;
    const categories = ["Todos", ...store.categories];
    target.innerHTML = categories.map((category, index) => `
      <button class="filter ${index === 0 ? "is-active" : ""}" type="button" data-filter="${escapeHtml(category)}">
        ${escapeHtml(category)}
      </button>
    `).join("");
  }

  function renderStore() {
    if (!document.querySelector(".store-app")) return;
    renderStoreSlider();
    renderStoreOffers();
    renderStoreCategories();
    renderStoreSections();
    requestAnimationFrame(startAutoScrollRails);
  }

  function renderFeaturedProducts() {
    const target = document.querySelector("[data-featured-products]");
    if (!target) return;
    const featured = store.products.filter((product) => product.featured).slice(0, 3);
    const products = featured.length ? featured : store.products.slice(0, 3);
    target.innerHTML = products.map((product) => productCard(product, "link")).join("");
  }

  function renderCategoryHighlights() {
    const target = document.querySelector("[data-category-highlights]");
    if (!target) return;
    target.innerHTML = store.categories.slice(0, 6).map((category) => {
      const total = store.products.filter((item) => item.category === category).length;
      return `
        <a class="category-tile" href="tienda.html?categoria=${encodeURIComponent(category)}">
          <span>${escapeHtml(category)}</span>
          <strong>${total}</strong>
        </a>
      `;
    }).join("");
  }

  function renderServices() {
    const target = document.querySelector("[data-services]");
    if (!target) return;
    target.innerHTML = store.services.map((service) => `<li>${escapeHtml(service)}</li>`).join("");
  }

  function renderCart() {
    const target = document.querySelector("[data-cart]");
    if (!target) return;
    const items = cartItems();
    if (items.length === 0) {
      target.innerHTML = `
        <div class="empty-state">
          <h3>Tu carrito esta vacio</h3>
          <p>Agrega productos desde la tienda para preparar una solicitud de compra o cotizacion.</p>
          <a class="button button--accent" href="tienda.html">Explorar tienda</a>
        </div>
      `;
      return;
    }
    const total = cartTotal();
    target.innerHTML = `
      ${items.map((item) => `
        <div class="cart-line">
          <strong>${escapeHtml(item.name)}<br><span class="muted">${money.format(item.price)} c/u</span></strong>
          <div class="qty" aria-label="Cantidad de ${escapeHtml(item.name)}">
            <button type="button" data-cart-dec="${escapeHtml(item.id)}" aria-label="Restar">-</button>
            <span>${escapeHtml(item.qty)}</span>
            <button type="button" data-cart-inc="${escapeHtml(item.id)}" aria-label="Sumar">+</button>
          </div>
          <strong>${money.format(item.price * item.qty)}</strong>
        </div>
      `).join("")}
      <div class="cart-total">
        <span>Total estimado</span>
        <strong>${money.format(total)}</strong>
      </div>
      <p class="notice">El total se confirma antes de cobrar. Instalacion, envio, disponibilidad y garantia pueden ajustar la cotizacion final.</p>
    `;
  }

  function renderCartSummary() {
    const target = document.querySelector("[data-cart-summary]");
    if (!target) return;
    const items = cartItems();
    target.innerHTML = items.length
      ? `<strong>${items.length}</strong><span>linea${items.length === 1 ? "" : "s"} en carrito</span><strong>${money.format(cartTotal())}</strong>`
      : "<strong>0</strong><span>productos seleccionados</span><strong>RD$0</strong>";
  }

  function buildWhatsAppOrder(extraMessage = "") {
    const items = cartItems();
    const lines = items.length
      ? items.map((item) => `- ${item.qty} x ${item.name} (${money.format(item.price)} c/u)`).join("\n")
      : "Quiero informacion sobre productos y servicios.";
    const totalLine = items.length ? `\nTotal estimado: ${money.format(cartTotal())}` : "";
    const message = `Hola FULLTECH, necesito ayuda con esta solicitud:\n${lines}${totalLine}${extraMessage ? `\nNotas: ${extraMessage}` : ""}`;
    return `https://wa.me/${store.company.whatsapp}?text=${encodeURIComponent(message)}`;
  }

  function buildProductWhatsApp(product) {
    const message = `Hola FULLTECH, quiero informacion de este producto:\n${product.name}\nCategoria: ${product.category}\nPrecio estimado: ${money.format(product.price)}${product.code ? `\nCodigo: ${product.code}` : ""}`;
    return `https://wa.me/${store.company.whatsapp}?text=${encodeURIComponent(message)}`;
  }

  function closeDrawer() {
    const header = document.querySelector(".site-header");
    const toggle = document.querySelector("[data-nav-toggle]");
    header?.classList.remove("is-open");
    document.body.classList.remove("nav-open");
    document.body.classList.remove("store-drawer-open");
    toggle?.setAttribute("aria-expanded", "false");
  }

  function openDrawer() {
    const header = document.querySelector(".site-header");
    const toggle = document.querySelector("[data-nav-toggle]");
    const drawer = document.querySelector(".store-drawer");
    if (!header || !toggle || !drawer) return;
    document.body.classList.add("store-drawer-open");
    toggle.setAttribute("aria-expanded", "true");
    drawer.querySelector("a, button")?.focus?.();
  }

  function openImagePreview(src, title) {
    const modal = document.querySelector("[data-image-modal]");
    if (!modal || !src) return;
    modal.querySelector("img").src = src;
    modal.querySelector("img").alt = title || "Imagen de producto";
    modal.querySelector("[data-image-title]").textContent = title || "Producto FULLTECH";
    modal.classList.add("is-open");
    document.body.classList.add("image-modal-open");
    modal.querySelector("[data-image-close]")?.focus?.();
  }

  function closeImagePreview() {
    const modal = document.querySelector("[data-image-modal]");
    if (!modal) return;
    modal.classList.remove("is-open");
    document.body.classList.remove("image-modal-open");
  }

  function startAutoScrollRails() {
    document.querySelectorAll(".store-benefits, .category-rail").forEach((rail) => {
      if (rail.dataset.autoScrollReady === "true") return;
      rail.dataset.autoScrollReady = "true";
      let direction = 1;
      window.setInterval(() => {
        if (rail.matches(":hover") || rail.scrollWidth <= rail.clientWidth) return;
        const next = rail.scrollLeft + direction * 1.4;
        if (next >= rail.scrollWidth - rail.clientWidth - 2) direction = -1;
        if (next <= 0) direction = 1;
        rail.scrollLeft = Math.max(0, Math.min(next, rail.scrollWidth - rail.clientWidth));
      }, 28);
    });
  }

  function prepareDrawer() {
    const toggle = document.querySelector("[data-nav-toggle]");
    const drawer = document.querySelector(".store-drawer");
    if (!toggle || !drawer) return;
    const drawerId = "fulltech-shared-drawer";
    drawer.id = drawerId;
    toggle.setAttribute("aria-controls", drawerId);
  }

  function wireEvents() {
    prepareDrawer();
    document.addEventListener("click", (event) => {
      const navToggle = event.target.closest("[data-nav-toggle]");
      if (navToggle) {
        const isOpen = document.body.classList.contains("store-drawer-open");
        if (isOpen) closeDrawer();
        else openDrawer();
        return;
      }
      if (event.target.closest("[data-nav-close]")) {
        closeDrawer();
        return;
      }
      if (document.querySelector(".site-header")?.classList.contains("is-open") && !event.target.closest(".nav__links") && !event.target.closest("[data-nav-toggle]")) closeDrawer();
      if (event.target.closest(".nav__links a")) {
        closeDrawer();
      }

      if (event.target.closest("[data-store-search-toggle]")) {
        document.querySelector("[data-store-search]")?.classList.toggle("is-open");
        return;
      }

      if (event.target.closest("[data-store-menu]")) {
        document.body.classList.toggle("store-drawer-open");
        return;
      }

      if (event.target.closest("[data-store-close]") || event.target.classList.contains("store-drawer-overlay")) {
        closeDrawer();
        return;
      }

      if (event.target.closest(".store-drawer a")) {
        closeDrawer();
      }

      const previewButton = event.target.closest("[data-image-preview]");
      if (previewButton) {
        openImagePreview(previewButton.dataset.imagePreview, previewButton.dataset.imageTitle);
        return;
      }

      if (event.target.closest("[data-image-close]") || event.target.classList.contains("image-modal")) {
        closeImagePreview();
        return;
      }

      const addButton = event.target.closest("[data-add-to-cart]");
      if (addButton) addToCart(addButton.dataset.addToCart);

      const filterButton = event.target.closest("[data-filter]");
      if (filterButton) {
        document.querySelectorAll("[data-filter]").forEach((button) => button.classList.remove("is-active"));
        filterButton.classList.add("is-active");
        state.category = filterButton.dataset.filter;
        renderProducts();
        renderStoreSections();
      }

      const inc = event.target.closest("[data-cart-inc]");
      const dec = event.target.closest("[data-cart-dec]");
      if (inc || dec) {
        const id = inc ? inc.dataset.cartInc : dec.dataset.cartDec;
        const current = cart();
        if (!current[id]) return;
        current[id].qty += inc ? 1 : -1;
        if (current[id].qty <= 0) delete current[id];
        saveCart(current);
        renderCart();
      }

      const clear = event.target.closest("[data-clear-cart]");
      if (clear) {
        saveCart({});
        renderCart();
      }
    });

    document.querySelectorAll("[data-product-search]").forEach((input) => {
      input.addEventListener("input", () => {
        state.query = input.value;
        renderProducts();
        renderStoreSections();
      });
    });

    document.querySelectorAll("[data-product-sort]").forEach((select) => {
      select.addEventListener("change", () => {
        state.sort = select.value;
        renderProducts();
        renderStoreSections();
      });
    });

    document.querySelectorAll("[data-whatsapp-order]").forEach((link) => {
      link.addEventListener("click", () => {
        const notes = document.querySelector("[data-order-notes]")?.value || "";
        link.href = buildWhatsAppOrder(notes);
      });
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        const wasOpen = document.body.classList.contains("store-drawer-open") || document.querySelector(".site-header")?.classList.contains("is-open");
        closeDrawer();
        closeImagePreview();
        if (wasOpen) document.querySelector("[data-nav-toggle]")?.focus?.();
      }
    });
  }

  function fillCompanyData() {
    document.querySelectorAll("[data-company]").forEach((node) => {
      const key = node.dataset.company;
      node.textContent = store.company[key] || "";
    });
    document.querySelectorAll("[data-whatsapp-link]").forEach((node) => {
      node.href = `https://wa.me/${store.company.whatsapp}`;
    });
    document.querySelectorAll("[data-email-link]").forEach((node) => {
      node.href = `mailto:${store.company.email}`;
    });
    if (!document.querySelector(".whatsapp-float")) {
      const link = document.createElement("a");
      link.className = "whatsapp-float";
      link.href = `https://wa.me/${store.company.whatsapp}`;
      link.setAttribute("aria-label", "Escribir por WhatsApp");
      link.innerHTML = '<svg viewBox="0 0 32 32" aria-hidden="true"><path d="M16.04 3.2c-7.06 0-12.8 5.72-12.8 12.76 0 2.25.59 4.44 1.72 6.37L3.13 29l6.84-1.79a12.77 12.77 0 0 0 6.07 1.55h.01c7.05 0 12.79-5.72 12.79-12.76S23.1 3.2 16.04 3.2Zm0 23.39h-.01c-1.91 0-3.78-.51-5.42-1.48l-.39-.23-4.06 1.06 1.08-3.95-.26-.41a10.56 10.56 0 0 1-1.62-5.62c0-5.84 4.79-10.59 10.68-10.59 2.85 0 5.53 1.11 7.55 3.11a10.48 10.48 0 0 1 3.13 7.52c0 5.84-4.79 10.59-10.68 10.59Zm5.86-7.93c-.32-.16-1.9-.93-2.19-1.04-.29-.11-.5-.16-.71.16-.21.32-.82 1.04-1.01 1.25-.19.21-.37.24-.69.08-.32-.16-1.35-.5-2.58-1.59-.95-.85-1.6-1.9-1.79-2.22-.19-.32-.02-.49.14-.65.15-.15.32-.37.48-.56.16-.19.21-.32.32-.53.11-.21.05-.4-.03-.56-.08-.16-.71-1.7-.97-2.33-.25-.61-.52-.53-.71-.54l-.61-.01c-.21 0-.56.08-.85.4-.29.32-1.12 1.09-1.12 2.65s1.15 3.08 1.31 3.29c.16.21 2.27 3.45 5.5 4.84.77.33 1.37.53 1.84.68.77.24 1.47.21 2.02.13.62-.09 1.9-.77 2.17-1.52.27-.75.27-1.39.19-1.52-.08-.13-.29-.21-.61-.37Z"/></svg>';
      document.body.appendChild(link);
    }
    if (!document.querySelector(".store-drawer")) {
      document.body.insertAdjacentHTML("beforeend", `
        <div class="store-drawer-overlay" aria-hidden="true"></div>
        <aside class="store-drawer" aria-label="Menu de FULLTECH">
          <div class="drawer-head">
            <img src="assets/logo.png" alt="Logo FULLTECH">
            <div><strong>FULLTECH</strong><span>Tienda online</span></div>
            <button class="drawer-close" type="button" data-store-close aria-label="Cerrar menu">x</button>
          </div>
          <a href="index.html">Pagina principal</a>
          <a href="tienda.html">Tienda</a>
          <a href="servicios.html">Servicios</a>
          <a href="contacto.html">Contacto</a>
          <a href="carrito.html">Carrito <span data-cart-count>0</span></a>
          <a class="drawer-cta" data-whatsapp-link>Cotizar por WhatsApp</a>
          <div class="drawer-meta">829-477-0756<br>Higuey, La Altagracia</div>
        </aside>
      `);
      document.querySelectorAll("[data-whatsapp-link]").forEach((node) => {
        node.href = `https://wa.me/${store.company.whatsapp}`;
      });
    }
    if (!document.querySelector("[data-image-modal]")) {
      document.body.insertAdjacentHTML("beforeend", `
        <div class="image-modal" data-image-modal aria-hidden="true">
          <div class="image-modal__bar">
            <button type="button" data-image-close aria-label="Regresar">Regresar</button>
            <strong data-image-title>Producto FULLTECH</strong>
          </div>
          <img src="assets/logo.png" alt="Producto FULLTECH">
        </div>
      `);
    }
  }

  function hydrateQueryParams() {
    const params = new URLSearchParams(window.location.search);
    const category = params.get("categoria");
    if (category && store.categories.includes(category)) {
      state.category = category;
      setTimeout(() => {
        const button = document.querySelector(`[data-filter="${CSS.escape(category)}"]`);
        if (button) {
          document.querySelectorAll("[data-filter]").forEach((item) => item.classList.remove("is-active"));
          button.classList.add("is-active");
        }
        renderProducts();
      }, 0);
    }
  }

  fillCompanyData();
  renderFilters();
  renderProducts();
  renderFeaturedProducts();
  renderCategoryHighlights();
  renderStore();
  renderServices();
  renderCart();
  renderCartSummary();
  updateCartCount();
  hydrateQueryParams();
  wireEvents();
})();
