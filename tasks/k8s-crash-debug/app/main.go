package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	// ---
	// THE BUG IS HERE
	// This will cause a panic because the program is run with no arguments.
	// The developer needs to identify why this is panicking and fix it.
	// A simple fix is to remove this line or check the number of arguments.
	configPath := os.Args[1]
	fmt.Println("Loading config from:", configPath)
	// ---

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Hello, World! Service is running.")
	})

	log.Println("Starting server on port 8080")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatal(err)
	}
}
