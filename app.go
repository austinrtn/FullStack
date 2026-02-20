package main

import (
	"log"
	"net/http"
	"encoding/json"
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
	
	// Write bytes to file with permisions
	err = os.WriteFile(data.FileName, data.FileBytes, 0644)
	if err != nil {
		http.Error(res, "Error writing file", http.StatusBadRequest)
		return
	} else {
		log.Print("File Downloaded!")
	}
}
