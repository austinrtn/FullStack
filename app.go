package main

import (
	"path/filepath"
	"encoding/json"
	"log"
	"net/http"

	"fmt"
	"sync"
	//"strconv"
	"os"
)

const PORT = ":3000"

type ImgData struct {
	FileName string `json:"name"`
	FileBytes []byte `json:"file"`
}

type ImgPath struct {
	Path string `json:"path"`
}

var (
	clients = make(map[chan string] struct{})
	clientsMu sync.Mutex
)

func main() {
	var err error
	// Create a static file server using http.FileServer
	fs := http.FileServer(http.Dir("http"))

	// Set root directory
	http.Handle("/", fs)

	err = os.MkdirAll("photos", 0755)
	if err != nil {
		log.Printf("Error creating photos dir: %v", err)
		log.Fatal("Error creating photos directory on server")
		return
	}
	

	photos := http.FileServer(http.Dir("photos"))
	http.Handle("/photos/", http.StripPrefix("/photos", photos))

	//Handle function 
	http.HandleFunc("/savePhoto", savePhoto)
	http.HandleFunc("/getPhotos", getPhotos)
	http.HandleFunc("/deletePhoto", deletePhoto)
	http.HandleFunc("/events", sseHandler)

	// Listen to port, handle if error
	log.Printf("Listening to %s\n\n", PORT)
	err = http.ListenAndServe(PORT, nil)

	if err != nil {
		log.Fatal(err)
	}
}

func broadcast(msg string) {
	clientsMu.Lock()
	defer clientsMu.Unlock()

	for ch := range clients {
		select {
			case ch <- msg:
			default: 
		}
	}
}

func savePhoto(res http.ResponseWriter, req *http.Request) {
	// Create data instance to save JSON to
 	var imgData ImgData
        var err error
        // Decode json from req.BODY
        err = json.NewDecoder(req.Body).Decode(&imgData)
        // Check if JSON parsed
        if err != nil {
                http.Error(res, "Error parsing JSON", http.StatusBadRequest)
                return
        }
        defer req.Body.Close()

	// Write bytes to file with permisions 
	fileName := "photos/" + filepath.Base(imgData.FileName)
	err = os.WriteFile(fileName, imgData.FileBytes, 0644)
	if err == nil {
		log.Printf("File '%s' downloaded!", imgData.FileName)
		broadcast("refresh")
	} else {
		http.Error(res, "Error writing file", http.StatusBadRequest)
		return
	}
}

func sseHandler(res http.ResponseWriter, req *http.Request) {
	res.Header().Set("Content-Type", "text/event-stream")
	res.Header().Set("Cache-Control", "no-cache")
	res.Header().Set("Connection", "keep-alive")

	flusher, ok := res.(http.Flusher)

	if !ok {
		http.Error(res, "Streaming not supported", http.StatusInternalServerError)
		return
	}

	ch := make(chan string, 1)
	clientsMu.Lock()
	clients[ch] = struct{}{}
	clientsMu.Unlock()

	defer func() {
		clientsMu.Lock()	
		delete(clients, ch)
		clientsMu.Unlock()
	}()

	for {
		select {
		case msg := <-ch:
			fmt.Fprintf(res, "data: %s\n\n", msg)
			flusher.Flush()
		case <-req.Context().Done():
			return
		}
	}
}

func getPhotos(res http.ResponseWriter, req *http.Request) {
	res.Header().Set("Content-Type", "application/json")
	res.Header().Set("Cache-Control", "no-cache")

	files, err := os.ReadDir("photos")
	if err != nil {
		log.Fatalf("Error: %v", err)
		return
	}

	var imgPaths []ImgPath

	for _, f := range files {
		if f.IsDir() { continue	}

		filePath := filepath.Join("photos", f.Name())

		imgData := ImgPath{
			Path: filePath,
		}

		imgPaths = append(imgPaths, imgData)
	}

	json.NewEncoder(res).Encode(imgPaths)
}

func deletePhoto(res http.ResponseWriter, req *http.Request) {
	var imgPath ImgPath	

	json.NewDecoder(req.Body).Decode(&imgPath)
	err := os.Remove(imgPath.Path)

	if logError(nil, err) { return }

	broadcast(("refresh"))
}

func logError(msg *string, err error) bool{
	if err == nil { return false}
	if msg == nil {
		log.Printf("Error: %v\n", err)
	} else {
		log.Printf("%v %v\n", msg, err)
	}

	return true
}

