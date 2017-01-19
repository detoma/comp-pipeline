; docformat = 'rst'

;+
; Extract various image geometry parameters from the appropriate flat file.
;
; :Uses:
;   comp_inventory_header, comp_extract_time, comp_read_flats, sxpar
;
; :Returns:
;   structure
;
; :Params:
;   images : in, required, type="fltarr(620, 620, nimg)"
;     images to use to find field stop/occulter centers
;   headers : in, required, type="strarr(ntags, nimg)"
;     the fits headers from which we want the geometry
;   date_dir : in, required, type=string
;     the directory for containing the files for the date in question, used to
;     find the flat file
;
; :Author:
;   Joseph Plowman
;-
function comp_image_geometry, images, headers, date_dir
  @comp_constants_common
  @comp_config_common

  ; TODO: remove when done
  @comp_testing_common

  ; scan the headers to find out what observations the files contain
  comp_inventory_header, headers, beam, wave, pol, type, expose, $
                         cover, cal_pol, cal_ret
  mg_log, 'beams: %s', strjoin(strtrim(beam, 2), ','), name='comp', /debug

  ; get the time in the format preferred by read_flats
  time = comp_extract_time(headers, day, month, year, hours, mins, secs)
  comp_read_flats, date_dir, wave, beam, time, flat, flat_header, flat_waves, $
                   flat_names, flat_expose

  ; restrieve distortion coefficients in file: dx1_c, dy1_c, dx2_x, dy2_c
  restore, filename=filepath(distortion_coeffs_file, root=binary_dir)

  ; TODO: are the below correct? are we correcting for difference between
  ; FITS and IDL standards (off by 1)?

  occulter1 = {x:sxpar(flat_header, 'OXCNTER1') - nx / 2, $
               y:sxpar(flat_header, 'OYCNTER1') - 1024 + ny / 2, $
               r:sxpar(flat_header, 'ORADIUS1')}
  occulter2 = {x:sxpar(flat_header, 'OXCNTER2') - 1024 + nx / 2, $
               y:sxpar(flat_header, 'OYCNTER2') - ny / 2, $
               r:sxpar(flat_header, 'ORADIUS2')}

  ; field position
  field1 = {x:sxpar(flat_header, 'FXCNTER1') - nx / 2, $
            y:sxpar(flat_header, 'FYCNTER1') - 1024 + ny / 2, $
            r:sxpar(flat_header, 'FRADIUS1')}
  field2 = {x:sxpar(flat_header, 'FXCNTER2') - 1024 + nx / 2, $
            y:sxpar(flat_header, 'FYCNTER2') - ny / 2, $
            r:sxpar(flat_header, 'FRADIUS2')}

  ; beam -1: corona in UL (comp_extract1), beam 1: corona in LR (comp_extract2)

  ; TODO: actually use COMP_FIND_ANNULUS to find, don't just
  ; read from flats

  ind1 = where(beam gt 0, n_plus_beam)
  if (n_plus_beam gt 0) then begin
    im = comp_extract1(reform(images[*, *, ind1[0]]))
    sub1 = im

    ; remove distortion
    comp_apply_distortion, sub1, im, dx1_c, dy1_c, dx2_c, dy2_c

    comp_find_annulus, im, calc_occulter1, calc_field1, $
                       occulter_guess=[occulter1.x, $
                                       occulter1.y, $
                                       occulter1.r], $
                       field_guess=[field1.x, $
                                    field1.y, $
                                    field1.r], $
                       occulter_points=occulter_points1, $
                       field_points=field_points1

    ;calc_occulter1.x += nx / 2
    calc_occulter1.x += occulter1.x + nx / 2
    ;calc_occulter1.y += 1024 - ny / 2
    calc_occulter1.y += occulter1.y + 1024 - ny / 2
    ;calc_field1.x += nx / 2
    calc_field1.x += field1.x + nx / 2
    ;calc_field1.y += 1024 - ny / 2
    calc_field1.y += field1.y + 1024 - ny / 2
  
    mg_log, '%f, %f, %f, %f, %d', $
            time, calc_occulter1.x, calc_occulter1.y, calc_occulter1.r, ind1[0], $
            name='calc_occ_ul', /debug

    mg_log, '%f, %f, %f, %f, %d', $
            time, calc_field1.x, calc_field1.y, calc_field1.r, ind1[0], $
            name='calc_field_ul', /debug
  endif

  ind2 = where(beam lt 0, n_minus_beam)
  if (n_minus_beam gt 0) then begin
    im = comp_extract2(reform(images[*, *, ind2[0]]))
    sub2 = im

    ; remove distortion
    comp_apply_distortion, im, sub2, dx1_c, dy1_c, dx2_c, dy2_c

    comp_find_annulus, im, calc_occulter2, calc_field2, $
                       occulter_guess=[occulter2.x, $
                                       occulter2.y, $
                                       occulter2.r], $
                       field_guess=[field2.x, $
                                    field2.y, $
                                    field2.r], $
                       occulter_points=occulter_points2, $
                       field_points=field_points2

    ;calc_occulter2.x += 1024 - nx / 2
    calc_occulter2.x += field2.x + 1024 - nx / 2

    ;calc_occulter2.y += ny / 2
    calc_occulter2.y += occulter2.y + ny / 2

    ;calc_field2.x += 1024 - nx / 2
    calc_field2.x += field2.x + 1024 - nx / 2

    ;calc_field2.y += ny / 2
    calc_field2.y += field2.y + ny / 2

    mg_log, '%f, %f, %f, %f, %d', $
            time, calc_occulter2.x, calc_occulter2.y, calc_occulter2.r, ind2[0], $
            name='calc_occ_lr', /debug

    mg_log, '%f, %f, %f, %f, %d', $
            time, calc_field2.x, calc_field2.y, calc_field2.r, ind2[0], $
            name='calc_field_lr', /debug
  endif

  ; write flat centers

  mg_log, '%f, %f, %f, %f', $
          time, occulter1.x + nx / 2, occulter1.y + 1024 - ny / 2, occulter1.r, $
          name='flat_occ_ul', /debug
  mg_log, '%f, %f, %f, %f', $
          time, field1.x + nx / 2, field1.y + 1024 - nx / 2, field1.r, $
          name='flat_field_ul', /debug
  mg_log, '%f, %f, %f, %f', $
          time, occulter2.x + 1024 - nx / 2, occulter2.y + ny / 2, occulter2.r, $
          name='flat_occ_lr', /debug
  mg_log, '%f, %f, %f, %f', $
          time, field2.x + 1024 - nx / 2, field2.y + ny / 2, field2.r, $
          name='flat_field_lr', /debug

  ; P angles of post
  pang1 = sxpar(flat_header, 'POSTANG1')
  pang2 = sxpar(flat_header, 'POSTANG2')

  ; overlap P angle (from the field stop)
  delta_x = sxpar(flat_header, 'OXCNTER2') - sxpar(flat_header, 'OXCNTER1')
  delta_y = sxpar(flat_header, 'OYCNTER1') - sxpar(flat_header, 'OYCNTER2')
  overlap_angle = !radeg * atan(delta_y / delta_x)

;  dims = size(images, /dimensions)
;  for i = 0L, dims[2] - 1L do begin
;    if (beam[i] gt 0L) then begin
;      background = comp_extract1(images[*, *, i])
;    endif else begin
;      background = comp_extract2(images[*, *, i])
;    endelse
;    comp_find_annulus, background, occulter, field, error=error
;    if (error eq 0L) then begin
;      mg_log, 'unable to find center', name='comp', /info
;    endif else begin
;      mg_log, strjoin(strtrim([beam[i], $
;                               occulter.x, occulter.y, occulter.r, $
;                               field.x, field.y, field.r], 2), ', '), $
;              name='comp', /info
;    endelse
;  endfor

  ; TODO: remove when done
  mg_log, '%s', current_l1_filename, name='comp', /debug
  if (n_elements(current_l1_filename) gt 0L) then begin
    if (n_plus_beam gt 0) then begin
      bname = file_basename(current_l1_filename) + '.centering-ul.sav'
      save, occulter_points1, field_points1, sub1, $
            filename=filepath(bname, root=engineering_dir)
    endif
    if (n_minus_beam gt 0) then begin
      bname = file_basename(current_l1_filename) + '.centering-lr.sav'
      save, occulter_points2, field_points2, sub2, $
            filename=filepath(bname, root=engineering_dir)
    endif
  endif


  return, { occulter1: occulter1, $
            occulter2: occulter2, $
            field1: field1, $
            field2: field2, $
            post_angle1: pang1, $
            post_angle2: pang2, $
            delta_x: delta_x, $
            delta_y: delta_y, $
            overlap_angle: overlap_angle $
          }
end
