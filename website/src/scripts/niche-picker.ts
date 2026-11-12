const picker = document.querySelector<HTMLDialogElement>('#niche-picker');
const trigger = document.querySelector<HTMLButtonElement>('[data-niche-open]');
const value = document.querySelector<HTMLInputElement>('#businessType');
const label = document.querySelector<HTMLElement>('[data-niche-label]');

if (picker && trigger && value && label) {
  const search = picker.querySelector<HTMLInputElement>('#niche-search')!;
  const options = [...picker.querySelectorAll<HTMLButtonElement>('[data-niche-option]')];
  const count = picker.querySelector<HTMLElement>('[data-niche-results]')!;
  const empty = picker.querySelector<HTMLElement>('[data-niche-empty]')!;
  const normalize = (text: string): string => text.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase().trim();
  const filter = (): void => {
    const query = normalize(search.value);
    let matches = 0;
    options.forEach((option) => {
      const match = normalize(option.dataset.nicheOption ?? '').includes(query);
      option.closest<HTMLElement>('[data-niche-item]')!.hidden = !match;
      if (match) matches++;
    });
    count.textContent = `${matches} ${matches === 1 ? 'opción disponible' : 'opciones disponibles'}`;
    empty.hidden = matches !== 0;
  };
  trigger.addEventListener('click', () => {
    search.value = '';
    filter();
    options.forEach((option) => option.setAttribute('aria-pressed', String(option.dataset.nicheOption === value.value)));
    picker.showModal();
    trigger.setAttribute('aria-expanded', 'true');
    search.focus();
  });
  picker.querySelector('[data-niche-close]')?.addEventListener('click', () => picker.close());
  picker.addEventListener('click', (event) => {
    if (event.target === picker) picker.close();
  });
  picker.addEventListener('close', () => {
    trigger.setAttribute('aria-expanded', 'false');
    trigger.focus();
  });
  search.addEventListener('input', filter);
  options.forEach((option) => option.addEventListener('click', () => {
    value.value = option.dataset.nicheOption ?? '';
    label.textContent = value.value;
    trigger.classList.add('has-selection');
    trigger.closest('[data-field]')?.classList.remove('is-invalid');
    value.dispatchEvent(new Event('change', { bubbles: true }));
    picker.close();
  }));
}
