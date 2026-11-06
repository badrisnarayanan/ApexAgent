// Opens a screenshot large over the page. Any link marked data-zoom points at the full-size image;
// without script it still opens that image on its own, so the link works either way.
let dialog: HTMLDialogElement | undefined;

function open(link: HTMLAnchorElement) {
	if (!dialog) {
		dialog = document.createElement('dialog');
		dialog.className = 'zoom';
		dialog.innerHTML =
			'<button class="zoom-close" type="button" aria-label="Close">×</button><img alt="" />';
		// A click anywhere but the image closes it, as does Esc (the dialog's own behaviour).
		dialog.addEventListener('click', (e) => {
			if (!(e.target instanceof HTMLImageElement)) dialog?.close();
		});
		dialog.addEventListener('close', () => document.documentElement.classList.remove('zoom-open'));
		document.body.append(dialog);
	}
	const img = dialog.querySelector('img')!;
	img.src = link.href;
	img.alt = link.querySelector('img')?.alt ?? '';
	document.documentElement.classList.add('zoom-open');
	dialog.showModal();
}

document.addEventListener('click', (e) => {
	if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey) return;
	const link = (e.target as Element | null)?.closest<HTMLAnchorElement>('a[data-zoom]');
	if (!link) return;
	e.preventDefault();
	open(link);
});
