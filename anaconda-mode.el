;;; anaconda-mode.el --- Code navigation, documentation lookup and completion for Python

;; Copyright (C) 2013, 2014 by Malyshev Artem

;; Author: Malyshev Artem <proofit404@gmail.com>
;; URL: https://github.com/proofit404/anaconda-mode
;; Version: 0.1.0
;; Package-Requires: ((emacs "24") (json-rpc "0.0.1"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;; Code:

(require 'json-rpc)
(require 'etags)
(require 'python)


;;; Server.

(defvar anaconda-mode-debug nil
  "Turn on anaconda_mode debug logging.")

(defvar anaconda-mode-host "localhost"
  "Target host with anaconda_mode server.")

(defvar anaconda-mode-port 24970
  "Port for anaconda_mode connection.")

(defun anaconda-mode-python ()
  "Detect python executable."
  (let ((virtualenv python-shell-virtualenv-path))
    (if virtualenv
        (concat (file-name-as-directory virtualenv) "bin/python")
      "python")))

(defun anaconda-mode-python-args ()
  "Python arguments to run anaconda_mode server."
  (delq nil (list "anaconda_mode.py"
                  "--ip" anaconda-mode-host
                  "--port" (number-to-string anaconda-mode-port)
                  (when anaconda-mode-debug "--debug"))))

(defun anaconda-mode-command ()
  "Shell command to run anaconda_mode server."
  (cons (anaconda-mode-python)
	(anaconda-mode-python-args)))

(defvar anaconda-mode-directory
  (file-name-directory load-file-name)
  "Directory containing anaconda_mode package.")

(defvar anaconda-mode-process nil
  "Currently running anaconda_mode process.")

(defvar anaconda-mode-connection nil
  "Json Rpc connection to anaconda_mode process.")

(defun anaconda-mode-running-p ()
  "Check for running anaconda_mode server."
  (and anaconda-mode-process
       (not (null (process-live-p anaconda-mode-process)))
       (json-rpc-live-p anaconda-mode-connection)))

(defun anaconda-mode-bootstrap ()
  "Run anaconda-mode-command process."
  (let ((default-directory anaconda-mode-directory))
    (setq anaconda-mode-process
          (apply 'start-process
                 "anaconda_mode"
                 "*anaconda*"
                 (anaconda-mode-python)
                 (anaconda-mode-python-args)))
    (accept-process-output anaconda-mode-process)
    (setq anaconda-mode-connection
          (json-rpc-connect anaconda-mode-host anaconda-mode-port))))

(defun anaconda-mode-start-node ()
  "Start anaconda_mode server."
  (when (anaconda-mode-need-restart)
    (anaconda-mode-stop-node))
  (unless (anaconda-mode-running-p)
    (anaconda-mode-bootstrap)))

(defun anaconda-mode-stop-node ()
  "Stop anaconda-mode server."
  (when (anaconda-mode-running-p)
    (kill-process anaconda-mode-process)
    (json-rpc-close anaconda-mode-connection)
    (setq anaconda-mode-connection nil)))

(defun anaconda-mode-need-restart ()
  "Check if current `anaconda-mode-process'.
Return nil if it run under proper environment."
  (and (anaconda-mode-running-p)
       (not (equal (process-command anaconda-mode-process)
                   (anaconda-mode-command)))))


;;; Interaction.

(defun anaconda-mode-call (command &rest args)
  "Make remote procedure call for COMMAND.
ARGS are COMMAND argument passed to remote call."
  (anaconda-mode-start-node)
  (apply 'json-rpc anaconda-mode-connection command args))

(defun anaconda-mode-call-1 (command)
  ;; TODO: Remove this function ones plugin system will be implemented.
  ;; See #28.
  (anaconda-mode-call
   command
   (buffer-substring-no-properties (point-min) (point-max))
   (line-number-at-pos (point))
   (current-column)
   (or (buffer-file-name) "")))


;;; Minor mode.

(defvar anaconda-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "M-?") 'anaconda-mode-view-doc)
    (define-key map [remap find-tag] 'anaconda-mode-find-definition)
    (define-key map [remap find-tag-other-window] 'anaconda-mode-find-definition-other-window)
    (define-key map [remap find-tag-other-frame] 'anaconda-mode-find-definition-other-frame)
    (define-key map (kbd "M-r") 'anaconda-mode-find-reference)
    (define-key map (kbd "C-x 4 R") 'anaconda-mode-find-reference-other-window)
    (define-key map (kbd "C-x 5 R") 'anaconda-mode-find-reference-other-frame)
    map)
  "Keymap for `anaconda-mode'.")

;;;###autoload
(define-minor-mode anaconda-mode
  "Code navigation, documentation lookup and completion for Python.

\\{anaconda-mode-map}"
  :lighter " Anaconda"
  :keymap anaconda-mode-map
  (if anaconda-mode
      (add-hook 'completion-at-point-functions
                'anaconda-mode-complete-at-point nil t)
    (remove-hook 'completion-at-point-functions
                 'anaconda-mode-complete-at-point t)))


;;; Code completion.

(defun anaconda-mode-complete-at-point ()
  "Complete at point with anaconda_mode."
  (let* ((bounds (bounds-of-thing-at-point 'symbol))
         (start (or (car bounds) (point)))
         (stop (or (cdr bounds) (point))))
    (list start stop
          (completion-table-dynamic
           'anaconda-mode-complete-thing))))

(defun anaconda-mode-complete-thing (&rest ignored)
  "Complete python thing at point.
IGNORED parameter is the string for which completion is required."
  (mapcar (lambda (candidate) (plist-get candidate :name))
          (anaconda-mode-complete)))

(defun anaconda-mode-complete ()
  "Request completion candidates."
  (anaconda-mode-call-1 "complete"))


;;; View documentation.

(defun anaconda-mode-view-doc ()
  "Show documentation for context at point."
  (interactive)
  (anaconda-mode-display-doc (or (anaconda-mode-call-1 "doc")
                                 (error "No documentation found"))))

(defun anaconda-mode-display-doc (doc)
  "Display documentation buffer with contents DOC."
  (with-current-buffer (get-buffer-create "*anaconda-doc*")
    (view-mode -1)
    (erase-buffer)
    (insert doc)
    (view-mode 1)
    (display-buffer (current-buffer))))


;;; Jump to definition.

(defun anaconda-mode-locate-definition ()
  "Request definitions."
  (anaconda-mode-chose-module
   "Definition: "
   (anaconda-mode-call-1 "location")))

(defun anaconda-mode-definition-buffer ()
  "Get definition buffer or raise error."
  (apply #'anaconda-mode-file-buffer
         (or (anaconda-mode-locate-definition)
             (error "Can't find definition"))))

(defun anaconda-mode-find-definition ()
  "Find definition at point."
  (interactive)
  (switch-to-buffer (anaconda-mode-definition-buffer)))

(defun anaconda-mode-find-definition-other-window ()
  "Find definition at point in other window."
  (interactive)
  (switch-to-buffer-other-window (anaconda-mode-definition-buffer)))

(defun anaconda-mode-find-definition-other-frame ()
  "Find definition at point in other frame."
  (interactive)
  (switch-to-buffer-other-frame (anaconda-mode-definition-buffer)))


;;; Find reference.

(defun anaconda-mode-locate-reference ()
  "Request references."
  (anaconda-mode-chose-module
   "Reference: "
   (anaconda-mode-call-1 "reference")))

(defun anaconda-mode-reference-buffer ()
  "Get reference buffer or raise error."
  (apply #'anaconda-mode-file-buffer
         (or (anaconda-mode-locate-reference)
             (error "Can't find references"))))

(defun anaconda-mode-find-reference ()
  "Jump to reference at point."
  (interactive)
  (switch-to-buffer (anaconda-mode-reference-buffer)))

(defun anaconda-mode-find-reference-other-window ()
  "Jump to reference at point in other window."
  (interactive)
  (switch-to-buffer-other-window (anaconda-mode-reference-buffer)))

(defun anaconda-mode-find-reference-other-frame ()
  "Jump to reference at point in other frame."
  (interactive)
  (switch-to-buffer-other-frame (anaconda-mode-reference-buffer)))

(defun anaconda-mode-chose-module (prompt modules)
  "Completing read with PROMPT from MODULES.
Return cons of file name and line."
  (let ((user-chose (anaconda-mode-user-chose prompt modules)))
    (when user-chose
      (list (plist-get user-chose :module_path)
            (plist-get user-chose :line)
            (plist-get user-chose :column)))))

(defun anaconda-mode-user-chose (prompt hash)
  "With PROMPT ask user for HASH value."
  (when hash
    (plist-get hash (anaconda-mode-completing-read prompt (key-list hash)))))

(defun anaconda-mode-completing-read (prompt collection)
  "Call completing engine with PROMPT on COLLECTION."
  (cond
   ((eq (length collection) 1)
    (car collection))
   ((> (length collection) 1)
    (completing-read prompt collection))))

(defun key-list (hash)
  "Return sorted key list of HASH.
Keys must be a string."
  (let (keys)
    (maphash
     (lambda (k v) (add-to-list 'keys k))
     hash)
    (sort keys 'string<)))

(defun anaconda-mode-file-buffer (file line column)
  "Find FILE no select at specified LINE and COLUMN.
Save current position in `find-tag-marker-ring'."
  (let ((buf (find-file-noselect file)))
    (ring-insert find-tag-marker-ring (point-marker))
    (with-current-buffer buf
      (goto-char (point-min))
      (forward-line (1- line))
      (move-to-column column)
      buf)))

(provide 'anaconda-mode)

;;; anaconda-mode.el ends here
