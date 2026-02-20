function handleClick() {
	fetch("/helloWorld", {
		method: 'POST',
		headers: { 'Content-Type': 'application/json'},
		body: JSON.stringify({'val': 123})
	}).then(res => res.text());
}
