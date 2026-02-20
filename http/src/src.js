function handleClick() {
	const file = document.getElementById("file_btn").files[0];
	const file_name = file.name;
	const file_ext = file_name.split(".").pop();

	if (file_ext != "jpeg" && file_ext != "png" && file_ext != "jpg") {
		alert("Invalid file type.  Must be .png or .jpeg");
		return;
	}

	// Create file reader 
	const reader = new FileReader();
	// e is the event fired by the FileReader
	// e.target is the file reader itself
	// .result is where file contents are stored 
	reader.onload = (e) => {
		// File contents need to be base64 encoded for GO JSON parse
		const base64 = e.target.result.split(',')[1];
		fetch("/savePhoto", {
			method: 'POST',
			headers: { 'Content-Type': 'application/json'},
			body: JSON.stringify({
				"name": file_name,
				"file": base64,
			}),
		}).then(res => res.blob().then(() => {
			loadPhotos();
		}));
	}
	reader.readAsDataURL(file);
}

function loadPhotos() {
	const piclist = document.getElementById("piclist");
	fetch("/getPhotos")
	.then(res => res.json())
	.then(data => {
		if(data == null) return;
		piclist.innerHTML = "";
		console.log(data)
		for(let i = 0; i < data.length; i++) {
			let picData = data[i];
			piclist.innerHTML += "<img src="+ picData.path+" width=200><br>";
		}
	});
}

document.addEventListener("DOMContentLoaded", () => {
	loadPhotos();

	const events = new EventSource('/events');
	events.onmessage = () => loadPhotos();
});
