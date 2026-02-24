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
var lastImgName string = ""

type Client struct {
	//struct categories: 'ui', 'display'
	Category string
}

type ImgData struct {
	/// Used to parse JSON client image data from client 
	FileName string `json:"name"`
	FileBytes []byte `json:"file"`
}

type ImgPath struct {
	// Used to to send / recieve photo file paths JSON formated 
	Path string `json:"path"`
}

type AppState struct {
	Clients map[chan string] Client 
	Mu sync.Mutex
	PhotoDir []os.DirEntry

	PhotosAvailable bool
	PrevPhotosAvailable bool
}

func main() {
	var err error
	// Create a static file server using http.FileServer
	fs := http.FileServer(http.Dir("http"))

	// Set root directory
	http.Handle("/", fs)

	err = os.MkdirAll("photos", 0755)
	if err != nil {
		log.Fatal("Error creating photos directory on server")
		return
	}
	

	photos := http.FileServer(http.Dir("photos"))
	http.Handle("/photos/", http.StripPrefix("/photos", photos))

	photoDir, err := os.ReadDir("Photos")
	if err != nil {
		log.Fatal("Error accessing photo directory")
		return
	}

	appState := &AppState{
		Clients: make(map[chan string] Client),
		PhotoDir: photoDir,
		PhotosAvailable: false,
		PrevPhotosAvailable: false,
	}

	//Handle functions 
	http.HandleFunc("/savePhoto", savePhoto)
	http.HandleFunc("/getPhotos", getPhotos)
	http.HandleFunc("/deletePhoto", deletePhoto)
	http.HandleFunc("/getRandomPhoto", getRandomPhoto)
	http.HandleFunc("/events", func(res http.ResponseWriter, req *http.Request){
		sseHandler(appState, res, req)
	})

	// Listen to port, handle if error
	log.Printf("Listening to %s\n\n", PORT)
	err = http.ListenAndServe(PORT, nil)

	if err != nil {
		log.Fatal(err)
	}
}

/// Function that is ran when client enters server.  Creates string chanel for client 
/// and adds it to the client map.  Then listens for when messages are added to the client's chanel 
/// from server and sends to client until disconnect 
func sseHandler(appState *AppState, res http.ResponseWriter, req *http.Request) {
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
	category := req.URL.Query().Get("category")

	// Add client chanel to client map.  Lock map to ensure 'single file' adding of Clients.
	// Multiple Clients being connected at the same time without locking map can cause errors.
	ch := make(chan string, 1)
	appState.Mu.Unlock()
	appState.Clients[ch] = Client{Category: category}
	appState.Mu.Unlock()
	flusher.Flush()

	dir, err := os.ReadDir("photos")
	if err != nil {
		if logError(nil, err) { return }
	}

	flusher.Flush()

	defer func() {
		appState.Mu.Lock()
		delete(appState.Clients, ch)
		appState.Mu.Unlock()
	}()

	// Listen for messages to be added to the client's chanel, then flush it to the client 
	for {
		if category == "display" {
			if len(dir) == 0 {
				broadcast(appState, "display", "no_photos_available")	
			} else {
				broadcast(appState, "display", "no_photos_available")	
			}
		}

		select {
		case msg := <-ch:
			// if client has message
			fmt.Fprint(res, wrapData(msg))
			flusher.Flush()

		case <-req.Context().Done():
			// if client discconects 
			return
		}
	}
}

/// adds server message to client chanel that JS frontend listens for 
func broadcast(appState *AppState, clientCategory string, msg string) {
	// Lock from adding clients to client map to not modify
	// map while itereating through it 
	appState.Mu.Lock()
	defer appState.Mu.Unlock()

	// For each client chanel, send message through it 
	for ch := range appState.Clients {
		if clientCategory == "" || clientCategory == appState.Clients[ch].Category {
			select {
				case ch <- msg:
				default: 
			}
		}
	}
}

/// Sends list of photofile paths to client to load into HTML 
func getPhotos(appState *AppState, res http.ResponseWriter, req *http.Request) {
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
	dir, err := os.ReadDir("photos")
	if err != nil {
		if logError(nil, err) { return }
	}

	previousDirLen := len(dir)

	err = os.WriteFile(fileName, imgData.FileBytes, 0644)

	if err == nil {
		log.Printf("File '%s' downloaded!", imgData.FileName)
		// Send message to client to refresh image list 
		broadcast("ui", "refresh")
		if previousDirLen == 0 { broadcast("display", "photos_available") }
	} else {
		http.Error(res, "Error writing file", http.StatusBadRequest)
		return
	}
}


func deletePhoto(res http.ResponseWriter, req *http.Request) {
	var imgPath ImgPath	

	// Get path from JSON sent by client 
	json.NewDecoder(req.Body).Decode(&imgPath)
	err := os.Remove(imgPath.Path)

	if logError(nil, err) { return }

	broadcast("ui", "refresh")
}

func getRandomPhoto(res http.ResponseWriter, req *http.Request) {
	files, err := os.ReadDir("photos")
	if logError(nil, err) { return }

	var randFile os.DirEntry
	var filePath string 
	for {
		randFile = files[rand.IntN(len(files))] 
		filePath = filepath.Join("photos", randFile.Name())

		if len(files) > 1 && lastImgName != randFile.Name() { 
			lastImgName = randFile.Name()
			break 
		} else { break } 
	}

	fileExt := filepath.Ext(filePath)
	res.Header().Set("Content-Type", mime.TypeByExtension(fileExt))
	res.Header().Set("X-File-Name", randFile.Name())

	fileData, err := os.ReadFile(filePath)

	if logError(nil, err) { return }

	res.Write(fileData)
}

func logError(msg *string, err error) bool {
	if err == nil { return false}
	if msg == nil {
		log.Printf("Error: %v\n", err)
	} else {
		log.Printf("%v %v\n", msg, err)
	}

	return true
}

func wrapData(data string) string {
	str := fmt.Sprintf("data::%s\n", data)
	return str
}

var errInvalidFile = errors.New("invalid image type")

func checkImgValid(fileName string, isDir bool) (error) {
	if isDir { return errInvalidFile}
	fileExt := filepath.Ext(fileName)

	if fileExt != ".png" && fileExt != ".jpg" && fileExt != ".jpeg" { return errInvalidFile}
	return nil
}

