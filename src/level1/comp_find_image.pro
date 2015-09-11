; docformat = 'rst'

;+
; Procedure to find either the edge of the occulting disk or the edge of the
; field stop. The occulter or field stop is chosen by the keyword neg_pol which 
;
; A 3-element array is returned containing: The x-offset of the image, the
; y-offset of the image, and the image radius. The value of chi^2 (chisq) is
; optionally returned.
;
; :Examples:
;   For example, call like::
;
;     comp_find_image, data, radius_guess=radius_guess, drad=drad, /neg_pol
;
; :Uses:
;   comp_radial_der, comp_circfit
;
; :Params:
;   dat : in
;     the data array in which to locate the image
;
; :Keywords:
;   radius_guess :
;     the optional guess of the radius of the discontinuity. If not specified,
;     the default value is used
;   drad :
;     the +/- size of the radius which to scan. If not specified, a default
;     value is used.
;   neg_pol : 
;     if set, negative discontinuities (field stop) will be found, of not set,
;     the default is for positive discontinuities (occulter)
;
; :Author:
;   Tomczyk, modified by Sitongia
;-
function comp_find_image, dat, chisq=chisq, radius_guess=radius_guess, $
                          drad=drad, neg_pol=neg_pol
  compile_opt strictarr
  @comp_fitc_common

  debug = 0   ; 1=debug mode, 1=on, 0=off
  ans = ' '

  ; if guess of radius is input, use it, otherwise use default guess
  if (keyword_set(radius_guess)) then begin
    radius_guess = radius_guess
  endif else begin
    if (keyword_set(neg_pol)) then radius_guess = 295. else radius_guess = 224.
  endelse

  ; if number of points around radius is input, use it, otherwise use default value
  ; number of points (+/-) around radius for determination
  if (keyword_set(drad)) then drad = drad else drad=40.

  ; find limb positions, array of angles (theta) and limb positions (r) is returned
  r = comp_radial_der(dat, theta, radius_guess, drad, neg_pol=neg_pol)

  c = comp_circfit(theta, r)   ; fit positions to a circle
  mg_log, 'c: %s', strjoin(strtrim(c, 2), ', '), name='comp/find_image', /debug

  if (debug eq 1) then begin
    plot, theta, r, psym=3, yrange=[200, 340], ystyle=1, $
          xtitle='Angle', ytitle='Radial Position', charsize=1.5, $
          title='find_image'
    rfit = c[0] * cos(theta - c[1]) $
             + sqrt(c[0]^2 * cos(theta - c[1])^2 - c[0]^2 +c[2]^2)
    oplot, theta, rfit
    ;print,'chisq:',chisq
    read, 'enter return', ans
  endif

  a = [c[0] * cos(c[1]), c[0] * sin(c[1]), c[2]]

  return, a
end