import { FulltechStore as fallbackStore } from "./data.js";

(async function () {
  let store = fallbackStore;
  let storeSource = "fallback";
  const state = {
    category: "Todos",
    query: "",
    sort: "featured"
  };

  try {
    const apiBase = (window.FULLTECH_API_BASE_URL || "").replace(/\/$/, "");
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
            updatedAt: payload.updatedAt || fallbackStore.company.updatedAt
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

  const money = new Intl.NumberFormat("es-DO", {
    style: "currency",
    currency: "DOP",
    maximumFractionDigits: 0
  });

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
      const previous = button.textContent;
      button.textContent = "Agregado";
      button.classList.add("is-success");
      setTimeout(() => {
        button.textContent = previous || "Agregar";
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
          <img class="product-card__image" src="${escapeHtml(product.image)}" alt="${escapeHtml(product.name)}" loading="lazy">
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

  function wireEvents() {
    document.addEventListener("click", (event) => {
      const addButton = event.target.closest("[data-add-to-cart]");
      if (addButton) addToCart(addButton.dataset.addToCart);

      const filterButton = event.target.closest("[data-filter]");
      if (filterButton) {
        document.querySelectorAll("[data-filter]").forEach((button) => button.classList.remove("is-active"));
        filterButton.classList.add("is-active");
        state.category = filterButton.dataset.filter;
        renderProducts();
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
      });
    });

    document.querySelectorAll("[data-product-sort]").forEach((select) => {
      select.addEventListener("change", () => {
        state.sort = select.value;
        renderProducts();
      });
    });

    document.querySelectorAll("[data-whatsapp-order]").forEach((link) => {
      link.addEventListener("click", () => {
        const notes = document.querySelector("[data-order-notes]")?.value || "";
        link.href = buildWhatsAppOrder(notes);
      });
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
  renderServices();
  renderCart();
  renderCartSummary();
  updateCartCount();
  hydrateQueryParams();
  wireEvents();
})();
