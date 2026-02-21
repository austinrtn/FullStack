/// Sends selected picture to backend
function submitPhoto() {
	// Check for / get user selected file 
	const file = document.getElementById("file_btn").files[0];
	if(file == null || file == undefined) return;

	const file_name = file.name;
	const file_ext = file_name.split(".").pop();

	// Make sure correct file type (image)
	if (file_ext != "jpeg" && file_ext != "png" && file_ext != "jpg") {
		alert("Invalid file type.  Must be .png or .jpeg");
		return;
	}

	// Create file reader to extract bytes from selected image / file
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

/// Fills HTML with photos from server 
function loadPhotos() {
	const piclist = document.getElementById("piclist");

	// Get file paths for photos and load them into HTML 
	fetch("/getPhotos")
	.then(res => res.json())
	.then(data => {
		// No photos in server, or error retriving photos;
		if(data == null) {
				  piclist.innerHTML = "";
				  return;
		}
		piclist.innerHTML = "";
		for(let i = 0; i < data.length; i++) {
				let picData = data[i];
				
				// For each image file, create img HTML element with button to delete photo
				let html = "<img src=" + picData.path + " width=300>";
				html += "<button onclick=deletePhoto('" + picData.path + "')>X</button><br>";
				piclist.innerHTML += html;
		}
	});
}

// Remove photo from file server
function deletePhoto(path) {		
		  const options = {
					 method: 'POST',
					 headers: {'Content-Type': 'application/json'},
					 body: JSON.stringify({"path": path}),
		  }

		  fetch("/deletePhoto", options)
		  .then(res => res.text().then(() => {
					 loadPhotos();		 
		  }));
}

// Listen to messages from the server
document.addEventListener("DOMContentLoaded", () => {
	loadPhotos();

	const events = new EventSource('/events');
	events.onmessage = () => {
		  loadPhotos();
	} 
});
