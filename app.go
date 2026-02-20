package main

import (
	"path/filepath"
	"encoding/json"
	"log"
	"net/http"

	//"strconv"
	"os"
)

const PORT = ":3000"

type Data struct {
	FileName string `json:"name"`
	FileBytes []byte `json:"file"`
}

func main() {
	// Create a static file server using http.FileServer
	fs := http.FileServer(http.Dir("http"))

	// Set root directory
	http.Handle("/", fs)

	photos := http.FileServer(http.Dir("photos"))
	http.Handle("/photos/", http.StripPrefix("/photos", photos))

	//Handle function 
	http.HandleFunc("/helloWorld", helloWorld)

	// Listen to port, handle if error
	log.Printf("Listening to %s\n\n", PORT)
	err := http.ListenAndServe(PORT, nil)

	if err != nil {
		log.Fatal(err)
	}
}

func helloWorld(res http.ResponseWriter, req *http.Request) {
	// Create data instance to save JSON to
 	var data Data
        var err error
        // Decode json from req.BODY
        err = json.NewDecoder(req.Body).Decode(&data)
        // Check if JSON parsed
        if err != nil {
                http.Error(res, "Error parsing JSON", http.StatusBadRequest)
                return
        }
        defer req.Body.Close()

	err = os.MkdirAll("photos", 0755)
	if err != nil {
		log.Printf("Error creating photos dir: %v", err)
		log.Fatal("Error creating photos directory on server")
		return
	}
	
	// Write bytes to file with permisions
	fileName := "photos/" + filepath.Base(data.FileName)
	err = os.WriteFile(fileName, data.FileBytes, 0644)
	if err == nil {
		log.Printf("File '%s' downloaded!", data.FileName)
	} else {
		http.Error(res, "Error writing file", http.StatusBadRequest)
		return
	}
}
