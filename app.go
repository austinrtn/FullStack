package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math/rand/v2"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"mime"
)

const PORT = ":3000"

type ImgData struct {
	/// Used to parse JSON client image data from client 
	FileName string `json:"name"`
	FileBytes []byte `json:"file"`
}

type ImgPath struct {
	// Used to to send / recieve photo file paths JSON formated 
	Path string `json:"path"`
}

/// map structure to contain clients and their message chanels 
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

	//Handle functions 
	http.HandleFunc("/savePhoto", savePhoto)
	http.HandleFunc("/getPhotos", getPhotos)
	http.HandleFunc("/deletePhoto", deletePhoto)
	http.HandleFunc("/getRandomPhoto", getRandomPhoto)
	http.HandleFunc("/events", sseHandler)

	// Listen to port, handle if error
	log.Printf("Listening to %s\n\n", PORT)
	err = http.ListenAndServe(PORT, nil)

	if err != nil {
		log.Fatal(err)
	}
}

/// adds server message to client chanel that JS frontend listens for 
func broadcast(msg string) {
	// Lock from adding clients to client map to not modify
	// map while itereating through it 
	clientsMu.Lock()
	defer clientsMu.Unlock()

	// For each client chanel, send message through it 
	for ch := range clients {
		select {
			case ch <- msg:
			default: 
		}
	}
}

/// Saves photo selected and send from JS client to File Server
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
		// Send message to client to refresh image list 
		broadcast("refresh")
	} else {
		http.Error(res, "Error writing file", http.StatusBadRequest)
		return
	}
}

/// Function that is ran when client enters server.  Creates string chanel for client 
/// and adds it to the client map.  Then listens for when messages are added to the client's chanel 
/// from server and sends to client until disconnect 
func sseHandler(res http.ResponseWriter, req *http.Request) {
	// Set headers to ensure stream continues for life time of client-server connection
	res.Header().Set("Content-Type", "text/event-stream")
	res.Header().Set("Cache-Control", "no-cache")
	res.Header().Set("Connection", "keep-alive")

	// For flushing messages to client 
	flusher, ok := res.(http.Flusher)

	if !ok {
		http.Error(res, "Streaming not supported", http.StatusInternalServerError)
		return
	}

	// Add client chanel to client map.  Lock map to ensure 'single file' adding of clients.
	// Multiple clients being connected at the same time without locking map can cause errors.
	ch := make(chan string, 1)
	clientsMu.Lock()
	clients[ch] = struct{}{}
	clientsMu.Unlock()

	defer func() {
		clientsMu.Lock()	
		delete(clients, ch)
		clientsMu.Unlock()
	}()

	// Listen for messages to be added to the client's chanel, then flush it to the client 
	for {
		select {
		// if client has message
		case msg := <-ch:
			fmt.Fprintf(res, "data: %s\n\n", msg)
			flusher.Flush()
		// if client discconects 
		case <-req.Context().Done():
			return
		}
	}
}

/// Sends list of photofile paths to client to load into HTML 
func getPhotos(res http.ResponseWriter, req *http.Request) {
	res.Header().Set("Content-Type", "application/json")
	res.Header().Set("Cache-Control", "no-cache")

	// Get files from photos dir 
	files, err := os.ReadDir("photos")
	if err != nil {
		log.Fatalf("Error: %v", err)
		return
	}

	// Store imagePath structs to be converted into JSON 
	var imgPaths []ImgPath

	// For each file, create file path, convert into ImgPath struct and append to imgPaths
	for _, file := range files {
		if logError(nil, checkImgValid(file.Name(), file.IsDir())) { return }

		// Create photo filepath 
		filePath := filepath.Join("photos", file.Name())

		imgData := ImgPath{
			Path: filePath,
		}

		imgPaths = append(imgPaths, imgData)
	}

	// Send imgPaths to http response writer as JSON 
	json.NewEncoder(res).Encode(imgPaths)
}

func getRandomPhoto(res http.ResponseWriter, req *http.Request) {
	files, err := os.ReadDir("photos")
	if logError(nil, err) { return }

	randFile := files[rand.IntN(len(files))] 
	filePath := filepath.Join("photos", randFile.Name())

	fileExt := filepath.Ext(filePath)
	res.Header().Set("Content-Type", mime.TypeByExtension(fileExt))
	res.Header().Set("X-File-Name", randFile.Name())

	fileData, err := os.ReadFile(filePath)

	if logError(nil, err) { return }

	res.Write(fileData)
}

/// Remove photo from file server 
func deletePhoto(res http.ResponseWriter, req *http.Request) {
	var imgPath ImgPath	

	// Get path from JSON sent by client 
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

var errInvalidFile = errors.New("invalid image type")

func checkImgValid(fileName string, isDir bool) (error) {
	if isDir { return errInvalidFile}
	fileExt := filepath.Ext(fileName)

	if fileExt != ".png" && fileExt != ".jpg" && fileExt != ".jpeg" { return errInvalidFile}
	return nil
}
