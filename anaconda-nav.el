;;; anaconda-nav.el --- Navigating for anaconda-mode

;; Copyright (C) 2014 by Fredrik Bergroth

;; Author: Fredrik Bergroth <fbergroth@gmail.com>
;; URL: https://github.com/proofit404/anaconda-mode
;; Version: 0.1.0

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

(require 'dash)
(require 'cl-lib)

(defvar anaconda-nav-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-2] 'anaconda-nav-jump)
    (define-key map (kbd "RET") 'anaconda-nav-jump)
    (define-key map (kbd "n") 'anaconda-nav-next)
    (define-key map (kbd "p") 'anaconda-nav-prev)
    (define-key map (kbd "q") 'anaconda-nav-quit)
    map)
  "Keymap for `anaconda-nav-mode'.")

(defvar anaconda-nav--last-marker nil)
(defvar anaconda-nav--markers ())
(defvar anaconda-nav--window-configuration nil)

(defun anaconda-nav-next ()
  (interactive)
  (anaconda-nav-next-error 1 nil t))

(defun anaconda-nav-prev ()
  (interactive)
  (anaconda-nav-next-error -1 nil t))

(defun anaconda-nav-quit ()
  (interactive)
  (quit-window)
  (anaconda-nav--restore-window-configuration))

(defun anaconda-nav-pop-marker ()
  (interactive)
  (unless anaconda-nav--markers
    (error "No marker available"))

  (let* ((marker (pop anaconda-nav--markers))
         (buffer (marker-buffer marker)))
    (unless (buffer-live-p buffer)
      (error "Buffer no longer available"))
    (switch-to-buffer buffer)
    (goto-char (marker-position marker))
    (set-marker marker nil)))

(defun anaconda-nav-jump (&optional event)
  (interactive (list last-input-event))
  (when event (goto-char (posn-point (event-end event))))
  (anaconda-nav-next-error 0 nil nil))

(defun anaconda-nav (result &optional jump-if-single-item)
  (setq anaconda-nav--last-marker (point-marker))
  (if (and jump-if-single-item (= 1 (length result)))
      (anaconda-nav-display-item (car result) nil)
    (with-current-buffer (get-buffer-create "*anaconda-nav*")
      (view-mode -1)
      (erase-buffer)
      (setq-local overlay-arrow-position nil)

      (--> result
        (--group-by (cons (plist-get it :module)
                          (plist-get it :path)) it)
        (--each it (apply 'anaconda-nav--insert-module it)))

      (goto-char (point-min))
      (anaconda-nav-mode)
      (setq anaconda-nav--window-configuration (current-window-configuration))
      (delete-other-windows)
      (switch-to-buffer-other-window (current-buffer)))))

(defun anaconda-nav--insert-module (header &rest items)
  (insert (car header) "\n")
  (--each items (insert (anaconda-nav--item it) "\n"))
  (insert "\n"))

(defun anaconda-nav--item (item)
  (propertize
   (concat (propertize (format "%7d " (plist-get item :line))
                       'face 'compilation-line-number)
           (anaconda-nav--item-description item))
   'anaconda-nav-item item
   'follow-link t
   'mouse-face 'highlight))

(defun anaconda-nav--item-description (item)
  (cl-destructuring-bind (&key column name description type &allow-other-keys) item
    (cond ((string= type "module") "«module definition»")
          (t (let ((to (+ column (length name))))
               (when (string= name (substring description column to))
                 (put-text-property column to 'face 'highlight description))
               description)))))


(defun anaconda-nav--next-item (next)
  (let ((search (if next #'next-single-property-change
                  #'previous-single-property-change)))
    (-when-let (pos (funcall search (point) 'anaconda-nav-item))
      (if (get-text-property pos 'anaconda-nav-item) pos
        (funcall search pos 'anaconda-nav-item)))))


(defun anaconda-nav-next-error (&optional argp reset preview)
  (interactive "p")
  (with-current-buffer (get-buffer-create "*anaconda-nav*")
    (goto-char (cond (reset (point-min))
                     ((cl-minusp argp) (line-beginning-position))
                     ((cl-plusp argp) (line-end-position))
                     ((point))))

    (--dotimes (abs argp)
      (--if-let (anaconda-nav--next-item (cl-plusp argp))
          (goto-char it)
        (error "No more matches")))

    (setq-local overlay-arrow-position (copy-marker (line-beginning-position)))
    (--when-let (get-text-property (point) 'anaconda-nav-item)
      (anaconda-nav-display-item it preview))))

(defun anaconda-nav--flash-result (name)
  (isearch-highlight (point)
                     (if (string= (symbol-at-point) name)
                         (+ (point) (length name))
                       (point-at-eol)))
  (run-with-idle-timer 0.5 nil 'isearch-dehighlight))

(defun anaconda-nav-display-item (item preview)
  (cl-destructuring-bind (&key line column name path &allow-other-keys) item
    (with-current-buffer (find-file-noselect path)
      (goto-char (point-min))
      (forward-line (1- line))
      (forward-char column)
      (anaconda-nav--flash-result name)
      (set-window-point (display-buffer (current-buffer)) (point))
      (unless preview
        (anaconda-nav--switch-to-buffer (current-buffer))))))

(defun anaconda-nav--switch-to-buffer (buffer)
  (when (markerp anaconda-nav--last-marker)
    (push anaconda-nav--last-marker anaconda-nav--markers)
    (setq anaconda-nav--last-marker nil))

  (anaconda-nav--restore-window-configuration)
  (switch-to-buffer buffer))

(defun anaconda-nav--restore-window-configuration ()
  (when anaconda-nav--window-configuration
    (set-window-configuration anaconda-nav--window-configuration)
    (setq anaconda-nav--window-configuration nil)))

(define-derived-mode anaconda-nav-mode special-mode "anaconda-nav"
  (use-local-map anaconda-nav-mode-map))

(provide 'anaconda-nav)

;;; anaconda-nav.el ends here
