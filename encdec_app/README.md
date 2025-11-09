# EncDec App 🔒

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![GitHub stars](https://img.shields.io/github/stars/your-username/your-repo?style=for-the-badge)

A simple yet powerful file encryption and decryption app built with Flutter. It uses AES-256-GCM encryption with a unique "Twist 2.0" feature to provide strong security for your files.

## ✨ Features

*   **Strong Encryption:** Uses AES-256-GCM, a modern and secure authenticated encryption algorithm.
*   **"Twist 2.0" Security:** An additional layer of security that scrambles your data with a unique key derived from your passphrase and the file's metadata. This makes the encryption even more resistant to attacks.
*   **PBKDF2 Key Derivation:** Protects your passphrase against brute-force attacks using the industry-standard PBKDF2 algorithm.
*   **Cross-Platform:** Built with Flutter, it works on Android, iOS, Windows, macOS, and Linux.
*   **User-Friendly:** A simple and intuitive user interface for easy file encryption and decryption.
*   **Streaming Support:** Encrypts and decrypts large files efficiently without consuming a lot of memory.

## 📸 Screenshots

*(Add your app screenshots here)*

## 🚀 Getting Started

To get a local copy up and running, follow these simple steps.

### Prerequisites

*   [Flutter SDK](https://flutter.dev/docs/get-started/install)

### Installation

1.  Clone the repo
    ```sh
    git clone https://github.com/your-username/your-repo.git
    ```
2.  Install packages
    ```sh
    flutter pub get
    ```
3.  Run the app
    ```sh
    flutter run
    ```

## 📖 How to Use

1.  **Enter a Passphrase:** This will be used to encrypt and decrypt your files. Make sure to use a strong and memorable passphrase.
2.  **Select an Input File:** Tap the "Select Input File" button to choose the file you want to encrypt or decrypt.
3.  **Start:** Tap the "Start" button to begin the encryption or decryption process.
4.  **Choose Output Location:** You will be prompted to choose a location to save the output file.

## 🛡️ Security

This app takes security seriously. Here's a breakdown of the security features:

*   **AES-256-GCM:** The core encryption algorithm is AES-256-GCM, which is a widely used and secure authenticated encryption algorithm. It not only encrypts your data but also ensures its integrity.
*   **PBKDF2:** The encryption key is derived from your passphrase using PBKDF2 with 100,000 iterations. This makes it very difficult for an attacker to guess your passphrase using brute-force attacks.
*   **"Twist 2.0":** This is a custom feature that adds an extra layer of security. It generates a unique keystream for each file based on your passphrase and the file's name and size. This keystream is then XORed with your data before encryption, making the ciphertext unique for each file and more resistant to analysis.

## 🤝 Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

1.  Fork the Project
2.  Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3.  Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4.  Push to the Branch (`git push origin feature/AmazingFeature`)
5.  Open a Pull Request

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.