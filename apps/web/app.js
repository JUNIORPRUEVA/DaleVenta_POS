import { FulltechStore as store } from "./data.js";

(function () {
  const money = new Intl.NumberFormat("es-DO", {
    style: "currency",
    currency: "DOP",
    maximumFractionDigits: 0
  });

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
  }

  function updateCartCount() {
    const count = Object.values(cart()).reduce((sum, item) => sum + item.qty, 0);
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
    const button = document.querySelector(`[data-add-to-cart="${productId}"]`);
    if (button) {
      button.textContent = "Agregado";
      setTimeout(() => {
        button.textContent = "Agregar al carrito";
      }, 900);
    }
  }

  function renderProducts(category) {
    const target = document.querySelector("[data-products]");
    if (!target) return;
    const products = category && category !== "Todos"
      ? store.products.filter((item) => item.category === category)
      : store.products;

    target.innerHTML = products.map((product) => `
      <article class="product-card">
        <img class="product-card__image" src="${product.image}" alt="${product.name}" loading="lazy">
        <div class="product-card__body">
          <div class="product-card__meta">
            <span>${product.category}</span>
            <span>Garantia ${product.warranty}</span>
          </div>
          <h3>${product.name}</h3>
          <p>${product.description}</p>
          <div class="price">${money.format(product.price)}</div>
          <button class="button" type="button" data-add-to-cart="${product.id}">Agregar al carrito</button>
        </div>
      </article>
    `).join("");
  }

  function renderFilters() {
    const target = document.querySelector("[data-filters]");
    if (!target) return;
    const categories = ["Todos", ...store.categories];
    target.innerHTML = categories.map((category, index) => `
      <button class="filter ${index === 0 ? "is-active" : ""}" type="button" data-filter="${category}">
        ${category}
      </button>
    `).join("");
  }

  function renderFeaturedProducts() {
    const target = document.querySelector("[data-featured-products]");
    if (!target) return;
    target.innerHTML = store.products.slice(0, 3).map((product) => `
      <article class="product-card">
        <img class="product-card__image" src="${product.image}" alt="${product.name}" loading="lazy">
        <div class="product-card__body">
          <div class="product-card__meta"><span>${product.category}</span><span>${product.warranty}</span></div>
          <h3>${product.name}</h3>
          <p>${product.description}</p>
          <div class="price">${money.format(product.price)}</div>
          <a class="button" href="catalogo.html">Ver catalogo</a>
        </div>
      </article>
    `).join("");
  }

  function renderCart() {
    const target = document.querySelector("[data-cart]");
    if (!target) return;
    const items = Object.values(cart());
    if (items.length === 0) {
      target.innerHTML = '<p class="lead">Tu carrito esta vacio. Agrega productos desde el catalogo para preparar tu pedido.</p>';
      return;
    }
    const total = items.reduce((sum, item) => sum + item.price * item.qty, 0);
    target.innerHTML = `
      ${items.map((item) => `
        <div class="cart-line">
          <strong>${item.name}<br><span class="muted">${money.format(item.price)} c/u</span></strong>
          <div class="qty">
            <button type="button" data-cart-dec="${item.id}">-</button>
            <span>${item.qty}</span>
            <button type="button" data-cart-inc="${item.id}">+</button>
          </div>
          <strong>${money.format(item.price * item.qty)}</strong>
        </div>
      `).join("")}
      <h3>Total estimado: ${money.format(total)}</h3>
      <p class="notice">Los precios pueden variar segun disponibilidad, instalacion requerida y alcance tecnico. FULLTECH confirmara el total antes de cobrar.</p>
    `;
  }

  function buildWhatsAppOrder() {
    const items = Object.values(cart());
    const message = items.length
      ? `Hola FULLTECH, quiero cotizar/comprar:%0A${items.map((item) => `- ${item.qty} x ${item.name} (${money.format(item.price)} c/u)`).join("%0A")}`
      : "Hola FULLTECH, quiero informacion sobre productos y servicios.";
    return `https://wa.me/${store.company.whatsapp}?text=${message}`;
  }

  function wireEvents() {
    document.addEventListener("click", (event) => {
      const addButton = event.target.closest("[data-add-to-cart]");
      if (addButton) addToCart(addButton.dataset.addToCart);

      const filterButton = event.target.closest("[data-filter]");
      if (filterButton) {
        document.querySelectorAll("[data-filter]").forEach((button) => button.classList.remove("is-active"));
        filterButton.classList.add("is-active");
        renderProducts(filterButton.dataset.filter);
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
    });

    document.querySelectorAll("[data-whatsapp-order]").forEach((link) => {
      link.addEventListener("click", () => {
        link.href = buildWhatsAppOrder();
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

  fillCompanyData();
  renderFilters();
  renderProducts();
  renderFeaturedProducts();
  renderCart();
  updateCartCount();
  wireEvents();
})();
