package main

import (
	"log"
	"net/http"
)

const PORT = ":3000"

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
	log.Println("Hello world!")
}
