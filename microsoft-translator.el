;;; microsoft-translator.el --- Emacs interface to Microsoft Translator -*- lexical-binding: t; -*-

;; Copyright (C) 2015 by Ryo Fujimoto

;; Author: Ryo Fujimoto <fujimisakri@gmail.com>
;; URL: https://github.com/fujimisakari/microsoft-translator
;; Version: 1.0.0

;;; License:
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; To use this package, add these lines to your init.el or .emacs file:
;;
;;  (require 'microsoft-translator)
;;  (setq microsoft-translator-client-id "<Your Client ID>")
;;  (setq microsoft-translator-client-secret "<Your Client Secret>")
;;
;; ----------------------------------------------------------------
;;
;; Translating by specifying the from<source-language> and to<target-language>.
;; M-x microsoft-translator-translate
;;
;; Automatic translation without specifying the from<source-language> and to<target-language>.
;; M-x microsoft-translator-auto-translate
;;

;;; Code:

(eval-when-compile (require 'cl))
(require 'request)

(defgroup microsoft-translator nil
  "microsoft-translator group"
  :group 'convenience)

(defcustom microsoft-translator-client-id nil
  "Your Client ID of Microsoft Azure Marketplace"
  :type 'string
  :group 'microsoft-translator)

(defcustom microsoft-translator-client-secret nil
  "Your Client Secret of Microsoft Azure Marketplace"
  :type 'string
  :group 'microsoft-translator)

(defcustom microsoft-translator-default-from nil
  "default from-language"
  :type 'string
  :group 'microsoft-translator)

(defcustom microsoft-translator-default-to nil
  "default to-language"
  :type 'string
  :group 'microsoft-translator)

(defcustom microsoft-translator-use-language-by-auto-translate nil
  "Language to be used in the automatic translation"
  :type 'string
  :group 'microsoft-translator)

(defconst microsoft-translator-token-url "https://datamarket.accesscontrol.windows.net/v2/OAuth2-13")
(defconst microsoft-translator-scope "http://api.microsofttranslator.com")
(defconst microsoft-translator-grant-type "client_credentials")
(defconst microsoft-translator-translate-url "http://api.microsofttranslator.com/V2/Ajax.svc/Translate")
(defconst microsoft-translator-buffer-name "*Microsoft Translator*")
(defconst microsoft-translator-english-chars "[:ascii:]")

(defvar microsoft-translator-access-token nil
  "Set the Token for each post")

(defvar microsoft-translator-supported-languages-alist
  '(("Arabic"              . "ar")
    ("Bosnian"             . "bs-Latn")
    ("Bulgarian"           . "bg")
    ("Catalan"             . "ca")
    ("Croatian"            . "hr")
    ("Czech"               . "cs")
    ("Danish"              . "da")
    ("Dutch"               . "nl")
    ("English"             . "en")
    ("Estonian"            . "et")
    ("Finnish"             . "fi")
    ("French"              . "fr")
    ("German"              . "de")
    ("Greek"               . "el")
    ("Haitian Creole"      . "ht")
    ("Hindi"               . "hi")
    ("Hungarian"           . "hu")
    ("Indonesian"          . "id")
    ("Irish"               . "ga")
    ("Italian"             . "it")
    ("Japanese"            . "ja")
    ("Korean"              . "ko")
    ("Latvian"             . "lv")
    ("Lithuanian"          . "lt")
    ("Malay"               . "ms")
    ("Maltese"             . "mt")
    ("Norwegian"           . "no")
    ("Persian"             . "fa")
    ("Polish"              . "pl")
    ("Portuguese"          . "pt")
    ("Romanian"            . "ro")
    ("Russian"             . "ru")
    ("Slovak"              . "sk")
    ("Slovenian"           . "sl")
    ("Spanish"             . "es")
    ("Swahili"             . "sw")
    ("Swedish"             . "sv")
    ("Thai"                . "th")
    ("Turkish"             . "tr")
    ("Ukrainian"           . "uk")
    ("Urdu"                . "ur")
    ("Vietnamese"          . "vi")
    ("Welsh"               . "cy"))
  "Alist of the languages supported by Microsoft Translator.

Each element is a cons-cell of the form (NAME . CODE), where NAME
is a human-readable language name and CODE is its code used as a
query parameter in HTTP requests.")

(defgroup microsoft-translator-faces nil
  "Faces for syntax highlighting."
  :group 'microsoft-translator
  :group 'faces)

(defface microsoft-translator-header-title
  '((((class color) (background light))
     (:foreground "blue"))
    (((class color) (background dark))
     (:foreground "lime green")))
  "Face used for displaying the header-title."
  :group 'microsoft-translator-faces)

(defun microsoft-translator-supported-languages ()
  "Return a list of names of languages supported by Microsoft Translator."
  (mapcar #'car microsoft-translator-supported-languages-alist))

(defun microsoft-translator-language-abbreviation (language)
  "Return the abbreviation of LANGUAGE."
  (cdr (assoc language microsoft-translator-supported-languages-alist)))

(defun microsoft-translator--header-title (from to)
  "Result buffer header-title text"
  (format "%s\n%s"
          (format "Translate from %s to %s:" from to)
          "------------------------------------"))

(defun microsoft-translator--initialize ()
  (if (get-buffer microsoft-translator-buffer-name)
      (kill-buffer microsoft-translator-buffer-name))
  (setq microsoft-translator-access-token nil))

(defun microsoft-translator--process (translate-text from to)
  "The main process"
  (microsoft-translator--initialize)
  (microsoft-translator--get-access-token)
  (unless microsoft-translator-access-token
    (error "Failed to get access token"))
  (microsoft-translator--translating translate-text from to))

(defun microsoft-translator--get-access-token ()
  (request
   microsoft-translator-token-url
   :type "POST"
   :sync t
   :data `(("client_id" . ,microsoft-translator-client-id)
           ("client_secret" . ,microsoft-translator-client-secret)
           ("scope" . ,microsoft-translator-scope)
           ("grant_type" . ,microsoft-translator-grant-type))
   :parser 'json-read
   :success (function*
             (lambda (&key data &allow-other-keys)
               (setq microsoft-translator-access-token (assoc-default 'access_token data))))
   :error (function* (error "get-access-token error"))))

(defun microsoft-translator--translating (translate-text from to)
  (request
   microsoft-translator-translate-url
   :type "GET"
   :sync t
   :headers `(("Authorization" . ,(format "bearer %s" microsoft-translator-access-token)))
   :params `(("text" . ,translate-text)
             ("to" . ,(microsoft-translator-language-abbreviation to))
             ("from" . ,(microsoft-translator-language-abbreviation from))
             ("contentType" . "text/plain")
             ("category" . "general"))
   :parser 'buffer-string
   :success (function* (lambda (&key data &allow-other-keys)
                         (when data
                           (with-current-buffer (get-buffer-create microsoft-translator-buffer-name)
                             (erase-buffer)
                             (insert (microsoft-translator--header-title from to))
                             (put-text-property (point-min) (point-at-eol) 'face 'microsoft-translator-header-title)
                             (insert (format "\n\n%s\n\n%s" translate-text (substring data 2 (1- (length data)))))
                             (setq buffer-read-only t)
                             (pop-to-buffer (current-buffer))
                             (goto-char (point-min))))))
   :error (function* (error "translating error"))))

(defun microsoft-translator--completing-read (prompt default-input)
    (completing-read prompt
                     microsoft-translator-supported-languages-alist
                     nil t default-input nil))

(defun microsoft-translator--read-from-and-to ()
  (let* ((from (microsoft-translator--completing-read "Translate from: " microsoft-translator-default-from))
         (to (microsoft-translator--completing-read (format "Translate from %s to: " from) microsoft-translator-default-to)))
    `(,from . ,to)))

(defun microsoft-translator--read-from-and-to-by-text (translate-text)
  (let ((asciip (string-match
                 (format "\\`[%s]+\\'" microsoft-translator-english-chars)
                 translate-text)))
    (if asciip
        `("English" . ,microsoft-translator-use-language-by-auto-translate)
      `(,microsoft-translator-use-language-by-auto-translate . "English"))))

(defun microsoft-translator--region-or-read-string ()
  (cond
   (mark-active
    (buffer-substring-no-properties (region-beginning) (region-end)))
   (t
    (let ((symbol-name-at-cursor (thing-at-point 'symbol))
          (translate-text nil))
      (if symbol-name-at-cursor
          (progn
            (setq translate-text (read-string (format "Translate Text(default \"%s\"): " symbol-name-at-cursor)))
            (unless translate-text
              (setq translate-text symbol-name-at-cursor)))
        (setq translate-text (read-string "Translate Text: ")))
      translate-text))))

;;;###autoload
(defun microsoft-translator-auto-translate ()
  "Read a string in the minibuffer with from-to is auto."
  (interactive)
  (let* ((translate-text (microsoft-translator--region-or-read-string))
         (from-and-to (microsoft-translator--read-from-and-to-by-text translate-text))
         (from (car from-and-to))
         (to (cdr from-and-to)))
    (microsoft-translator--process translate-text from to)))

;;;###autoload
(defun microsoft-translator-translate ()
  "Read a string in the minibuffer with completion."
  (interactive)
  (let* ((translate-text (microsoft-translator--region-or-read-string))
         (from-and-to (microsoft-translator--read-from-and-to))
         (from (car from-and-to))
         (to (cdr from-and-to)))
    (microsoft-translator--process translate-text from to)))

(provide 'microsoft-translator)

;;; microsoft-translator.el ends here
