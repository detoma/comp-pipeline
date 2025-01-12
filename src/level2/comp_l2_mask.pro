 ; docformat = 'rst'

;+
; Create a mask for CoMP images in the 620x620 spatial resolution. Include the
; occulting disk, field stop, occulter post and the overlap of the two
; sub-images.
;
;
; :Examples:
;   For example, call like::
;
;     mask = comp_l2_mask(header)
;
; :Uses:
;   comp_constants_common, comp_mask_constants_common, comp_initialize,
;   comp_disk_mask, comp_field_mask, comp_post_mask, comp_overlap_mask
;
; :Returns:
;   mask image, `fltarr(1024, 1024)`
;
; :Params:
;   date_dir : in, required, type=string
;     date to process, in YYYYMMDD format
;   fits_header : in, required
;     the primary header of the CoMP FITS file
;   mask : out, optional, type="fltarr(1024, 1024)"
;     mask image
;
; :Keywords:
;   no_post : in, optional, type=boolean
;     set to not mask the post
;   occulter_offset : in, optional, type=float, default=epoch value
;     set to override the occulter offset value set in the epoch file; this is
;     the amount to overmask the occculter
;   field_offset : in, optional, type=float, default=epoch value
;     set to override the field offset value set in the epoch file; this is
;     the amount to overmask the field stop
;
; :Author:
;   MLSO Software Team
;
; :History:
;   added comments 10/23/14 ST
;   removed post_rotation fudge factor 11/14/14 ST
;   see git log for other changes
;   MG  added option for occulter_offset and field-offset 03/2024
;   GdT fixed bugs in no_post option 03/2023 
;   GdT added option for using occulter radius in header - needed for rest wavelength computation 03/2024
;-
function comp_l2_mask, fits_header, no_post=no_post, $
                       image_occulter_radius=image_occulter_radius, $
                       occulter_offset=override_occulter_offset, $
                       field_offset=override_field_offset
  
  compile_opt strictarr
  @comp_constants_common
  @comp_mask_constants_common

  use_occulter_offset = n_elements(override_occulter_offset) gt 0L $
                          ? override_occulter_offset $
                          : occulter_offset
  use_field_offset = n_elements(override_field_offset) gt 0L $
                       ? override_field_offset $
                       : field_offset

  ; get parameters from FITS header

  ; look for new keyword
  fradius = sxpar(fits_header, 'FRADIUS', count=count)

  ; if img_occulter_radius is set, use the occulter radius recorded in the
  ; header
  ; if not set, uses the average value of the occulter radius

  if (not keyword_set(image_occulter_radius)) then begin
    occulter_id = sxpar(fits_header, 'OCC-ID')
    occulter_index = where(occulter_ids eq occulter_id)
    occulter_radius = occulter_radii[occulter_index[0]]
  endif else begin
    occulter_radius =sxpar(fits_header, 'ORADIUS')
  endelse

  if (count eq 0) then begin
    ; old keywords 
    occulter = {x:sxpar(fits_header, 'CRPIX1') , $
                y:sxpar(fits_header, 'CRPIX2'), $
                r:((sxpar(fits_header, 'OCRAD1') $
                    + sxpar(fits_header, 'OCRAD2')) / 2.0)}
    field = {x:((sxpar(fits_header, 'FCENX1') $
                 + sxpar(fits_header, 'FCENX2')) / 2.0), $
             y:((sxpar(fits_header, 'FCENY1') $
                 + sxpar(fits_header, 'FCENY2')) / 2.0), $
             r:((sxpar(fits_header, 'FCRAD1') $
                 + sxpar(fits_header, 'FCRAD2')) / 2.0)}

    ; create the mask from individual masks

    ; occulter mask
    dmask = comp_disk_mask(occulter_radius + use_occulter_offset, $
                           xcen=occulter.x, ycen=occulter.y)

    ; field mask
    field_mask = comp_field_mask(field.r + use_field_offset, $
                                 xcen=field.x, ycen=field.y)

    mask = dmask * field_mask
  endif else begin
    ; for new headers subtract 1 to convert FITS coordinates to IDL coordinates 
    occulter = {x:sxpar(fits_header, 'CRPIX1') - 1.0, $
                y:sxpar(fits_header, 'CRPIX2') - 1.0, $
                r:comp_occulter_radius(sxpar(fits_header, 'OCC-ID'))}
    field = {x:sxpar(fits_header, 'FRPIX1') - 1.0, $
             y:sxpar(fits_header, 'FRPIX2') - 1.0, $
             r:comp_field_radius()}
    post_angle = sxpar(fits_header, 'POSTPANG')
    overlap_angle = sxpar(fits_header, 'OVRLPANG')
    p_angle = sxpar(fits_header, 'SOLAR_P0')

    ; create the mask from individual masks

    ; occulter mask
    dmask = comp_disk_mask(occulter_radius + use_occulter_offset, $
                           xcen=occulter.x, ycen=occulter.y)

    ; field mask
    field_mask = comp_field_mask(field.r + use_field_offset, $
                                 xcen=field.x, ycen=field.y)
  
    ; post mask
    ; pmask = comp_post_mask(post_angle + 180. - p_angle - post_rotation, 32.0)      ST 11/14/14
    ; pmask = comp_post_mask(post_angle + 180. - p_angle, post_width)
    
    ; now the image header has the right post angle
    if (not keyword_set(no_post)) then begin
      pmask = comp_post_mask(post_angle, post_width)
    endif else begin
      pmask = dmask * 0B + 1B
    endelse

    ; overlap mask
    omask = comp_overlap_mask(field.r, overlap_angle + p_angle, $
                              dx=(occulter.x - field.x), $
                              dy=(occulter.y - field.y))

    mask = dmask * field_mask * pmask * omask
  endelse

  return, mask
end


; main-level example program

date = '20170819'
comp_initialize, date
basename = '20170819.202136.comp.1074.iqu.3.fts.gz'
filename = filepath(basename, root='/hao/dawn/Data/CoMP/process.reprocess-check/20170819/level1')
fits_open, filename, fcb
fits_read, fcb, data, header, exten_no=0, /header_only
fits_close, fcb
mask = comp_l2_mask(header)

end
